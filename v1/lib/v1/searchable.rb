require_relative 'search_error'
require_relative 'repository'
require_relative 'schema'
require_relative 'searchable/facet'
require_relative 'searchable/filter'
require_relative 'searchable/query'
require_relative 'searchable/sort'
require 'tire'
require 'active_support/core_ext'

module V1

  module Searchable

    # Default pagination size for search results
    DEFAULT_PAGE_SIZE = 10

    # Default max page size
    MAX_PAGE_SIZE = 100
    
    # General query params that are not resource-specific
    BASE_QUERY_PARAMS = %w( q controller action sort_by sort_by_pin sort_order page page_size facets facet_size filter_facets fields callback _ x ).freeze

    def resource
      raise "Modules extending Searchable must define resource() method"
    end

    def build_queries(resource, filtered_search, params)
      queries = []
      queries << Searchable::Query.build_all(resource, filtered_search, params)
      queries << Searchable::Filter.build_all(resource, filtered_search, params)
      queries.any?
    end

    def build_facets(resource, search, params, global)
      Searchable::Facet.build_all(resource, search, params, global)
    end

    def build_sort(resource, search, params)
      Searchable::Sort.build_sort(resource, search, params)
    end

    def search(params={})
      validate_query_params(params)
      validate_field_params(params)

      search = Tire.search(Config.search_index + '/' + resource) do |search|
        global_facets = nil

        search.query do |query|
          query.filtered do |filtered|
            global_facets = !build_queries(resource, filtered, params)
          end
        end

        build_facets(resource, search, params, global_facets)
        build_sort(resource, search, params)

        search.from search_offset(params)
        search.size search_page_size(params)

        search.fields(params['fields'].to_s.split(/,\s*/)) if params['fields'].present?

        # for testability, this block should always return its search object
        search
      end

      begin
        if (Rails.env.development? rescue false)
          Rails.logger.debug "CURL: #{search.to_curl}"
        end
        return wrap_results(search, params)
      rescue Tire::Search::SearchRequestFailed => e
        error = JSON.parse(search.response.body)['error'] rescue nil
        raise InternalServerSearchError, error
      end
    end

    
    def search_offset(params)
      page = params["page"].to_i
      page == 0 ? 0 : search_page_size(params) * (page - 1)
    end

    def search_page_size(params)
      #TODO: raise error for invalid value, a la validate_field_params
      size = params["page_size"]
      if size.to_s == '0'
        0
      elsif size.to_i == 0
        DEFAULT_PAGE_SIZE
      elsif size.to_i > MAX_PAGE_SIZE
        MAX_PAGE_SIZE
      else
        size.to_i
      end
    end

    def wrap_results(search, params)
      results = search.results
      facet_size = get_facet_size(params)
      
      {
        'count' => results.total,
        'start' => search.options[:from],
        'limit' => search.options[:size],
        'docs' => format_results(results),
        'facets' => format_facets(results.facets, facet_size)
      }
    end

    def format_results(results)
      results.map do |doc|
        if doc['_source'].present?
          doc['_source'].delete_if {|k,v| k =~ /^_type/}
          doc['_source'].merge!({'score' => doc['_score']})
        else
          doc['fields'] || {}
        end
      end
    end

    def format_facets(facets, facet_size)
      return [] unless facets

      facet_keys = {
        'date_histogram' => 'entries',
        'terms' => 'terms',
        'geo_distance' => 'ranges',
        'range' => 'ranges'
      }

      facets.each do |name, payload|

        type = payload['_type']
        payload_key = facet_keys[type]
        facet_values = payload[payload_key]

        name =~ /(.+)\.(.*)$/
        modifier = $2
        
        if type == 'date_histogram'
          # Delete facets generated by the default date values of -9999 and 9999. It might
          # be possible to automatically exclude these with a built-in facet filter....
          payload[payload_key].delete_if {|value_hash| [-377705116800000, 253370764800000].include?(value_hash['time'])}
          
          # Format
          payload[payload_key].each do |value_hash|
            value_hash['time'] = format_date_facet(value_hash['time'], modifier)
          end

          # Sort: Fix backwards default sorting of date facets from ElasticSearch
          #TODO: refactor dupe sort calls into method
          payload[payload_key] = payload[payload_key].sort_by {|x| x['count']}.reverse
        elsif type == 'range' && %w( decade century ).include?(modifier)
          # Make range facet on a date field look like date_histogram with interval
          # Override payload_key to point to where we moving the data
          payload_key = 'entries'

          # Delete zero-count facet values to better emulate date_histogram facets
          facet_values.delete_if {|vh| vh['count'] == 0}
          
          # Format
          payload[payload_key] = facet_values.map do |value_hash|
            { 'time' => value_hash['from_str'], 'count' => value_hash['count'] }
          end

          # Sort
          payload[payload_key] = payload[payload_key].sort_by {|x| x['count']}.reverse

          payload['_type'] = 'date_histogram'
          payload.delete 'ranges'
        end

        if facet_size
          # trim this facet to the requested limit after it has been optionally re-sorted
          payload[payload_key] = payload[payload_key].first(facet_size.to_i)
        end

      end
    end

    def format_date_facet(value, interval=nil)
      # Value is from ElasticSearch and it is in UTC milliseconds since the epoch
      formats = {
        'day' => '%F',
        'month' => '%Y-%m',
        'year' => '%Y'
      }      

      # temporary hack to work around ElasticSearch adjusting timezones and breaking our dates
      offset = 5 * 60 * 60 * 1000 #5 hours in milliseconds
      # offset *= -1 if value < 0  #TODO: subtract for pre-epoch dates, add for post-epoch
      #      Rails.logger.debug "offset/value: #{offset} / #{value}"
      date = Time.at( (value+offset)/1000 ).to_date

      # Default to 'day' format (e.g. '1993-01-31')
      date.strftime(formats[interval] || '%F')
    end

    def validate_query_params(params)
      # Raises exception if any unrecognized search params are present. Query-based 
      # extensions (e.g: spatial.distance) are added here as well. Does not examine
      # contents of fields containing field names, such as sorting, facets, etc.
      invalid = params.keys - (BASE_QUERY_PARAMS + Schema.queryable_field_names(resource))
      if invalid.any?
        raise BadRequestSearchError, "Invalid field(s) specified in query: #{invalid.join(',')}"
      end
    end

    def validate_field_params(params)
      invalid = params['fields'].to_s.split(/,\s*/) - Schema.queryable_field_names(resource)
      if invalid.any?  
        raise BadRequestSearchError, "Invalid field(s) specified for fields parameter: #{invalid.join(',')}" 
      end
    end

    def id_to_private_id(ids)
      #TODO: use a cacheable filter here instead?
      search({'id' => ids.join(' OR ')})['docs'].inject({}) do |memo, doc|
        memo[doc['id']] = doc['_id']
        memo
      end
    end

    def fetch(ids)
      # Transparently translate "id" values from query to the "_id" values CouchDB expects
      # Accepts an array of ids or a string containing a comma separated list of ids
      ids = ids.split(/,\s*/) if ids.is_a?(String)

      id_map = id_to_private_id(ids)

      # Business logic: if they fetched one doc and it was 404, raise.
      if id_map.empty? && ids.size == 1
        raise NotFoundSearchError, "Document not found"
      end

      fetches = Repository.fetch(id_map.values)
      # fetched docs that were deleted in the repo will have a nil 'doc' field
      fetches['docs'].delete_if {|doc| doc.nil?}

      misses = ids - fetches['docs'].map {|doc| doc['id']}
      misses.each do |id|
        fetches['docs'] << { 'id' => id, 'error' => '404' }
      end

      {
        'docs' => fetches['docs'],
        'count' => fetches['docs'].size
      }
    end

    def get_facet_size(params)
      Searchable::FacetOptions.facet_size(params)
    end

    def verbose_debug(search)
      puts "CURL: #{search.to_curl}"
    end

  end

end
