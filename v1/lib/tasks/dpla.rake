require 'v1/search_engine'
require 'v1/repository'

namespace :v1 do

  # NOTE: Any task that calls a method that internally makes calls to Tire, must pass
  # the :environment symbol in the task() call so the Tire initializer gets called.

  desc "Tests river by posting test doc to CouchDB and verifying it in ElasticSearch"
  task :test_river => :environment do
    V1::SearchEngine::River.test_river
  end

  desc "Updates existing ElasticSearch schema *without* deleting the current index"
  task :update_search_schema => :environment do
    V1::SearchEngine.update_schema
  end

  desc "Deploys search index by updating dpla_alias and its river"
  task :deploy_search_index, [:index] => :environment do |t, args|
    raise "Missing required index argument to rake task" unless args.index
    V1::SearchEngine.deploy_index(args.index)
  end

  desc "Creates new ElasticSearch index"
  task :create_search_index => :environment do
    V1::SearchEngine.create_index 'foo'
  end

  desc "Lists existing ElasticSearch indices"
  task :search_indices => :environment do
    V1::SearchEngine.display_indices
  end

  desc "Deletes the named ElasticSearch index. Requires 'really' as second param to confirm delete."
  task :delete_search_index, [:index,:really] => :environment do |t, args|
    if args.really != 'really'
      raise "Missing/incorrect 'really' parameter. Hint: It must be the string: really"
    end
    V1::SearchEngine.safe_delete_index(args.index)
  end

  desc "Creates new ElasticSearch index and river"
  task :create_search_index_with_river => :environment do
    V1::SearchEngine.create_index_with_river
  end

  desc "Creates new ElasticSearch index and river and *immediately* deploys it"
  task :create_and_deploy_index => :environment do
    if Rails.env.production?
      raise "Refusing to run create_and_deploy_index in production b/c it would deploy an empty index"
    end
    V1::SearchEngine.create_and_deploy_index
  end

  desc "Re-creates ElasticSearch index"
  task :recreate_search_index => :environment do
    V1::SearchEngine.recreate_index!
  end

  desc "Re-creates ElasticSearch index, river and re-populates index with test dataset"
  task :recreate_search_env => :environment do
    V1::SearchEngine.recreate_env!
  end

  desc "Re-creates ElasticSearch river for the currently deployed index"
  task :recreate_river => :environment do
    V1::SearchEngine::River.recreate_river
  end

  #TODO: This is confusing to use.
  desc "Creates new ElasticSearch river, pointed at $index (defaults to currently deployed index)"
  task :create_river, [:index,:river] => :environment do |t, args|
    V1::SearchEngine::River.create_river('index' => args.index, 'river' => args.river)
  end

  desc "Deletes ElasticSearch river named '#{V1::Config.river_name}'"
  task :delete_river do
    V1::SearchEngine::River.delete_river or puts "River does not exist, so nothing to delete"
  end

  desc "Gets ElasticSearch river status"
  task :river_status do
    puts V1::SearchEngine::River.service_status
  end

  desc "Gets ElasticSearch search cluster status"
  task :search_status do
    puts V1::SearchEngine.service_status
  end

  desc "Gets number of docs in search index"
  task :search_doc_count do
    puts V1::SearchEngine.doc_count
  end

  desc "Displays the ElasticSearch search_endpoint the API is configured to use"
  task :search_endpoint do
    puts V1::Config.search_endpoint
  end

  desc "Displays the current schema in ElasticSearch, according to ElasticSearch."
  task :search_schema => :environment do
    puts V1::SearchEngine.search_schema
  end

  desc "Show API 'is_valid?' auth for a key"
  task :show_api_auth, [:key] do |t, args|
    puts "Authenticated?: #{ V1::Repository.authenticate_api_key(args.key) }"
  end
  
  desc "Deletes cached API auth for a single api_key"
  task :clear_cached_api_auth, [:key] => :environment do |t, args|
    previous = V1::ApiKey.clear_cached_auth(args.key)
    puts "Done. (was '#{previous}')"
  end
  
  desc "Displays the CouchDB repository_endpoint the API is configured to use"
  task :repo_endpoint do
    puts V1::Repository.reader_cluster_database.to_s
  end

  desc "Gets CouchDB repository status"
  task :repo_status do
    puts V1::Repository.service_status
  end

  desc "Creates new CouchDB repository database"
  task :recreate_repo_database do
    V1::Repository.recreate_doc_database
    V1::Repository.recreate_users
  end

  desc "Creates new CouchDB auth token database"
  task :recreate_repo_api_key_database do
    V1::Repository.recreate_api_keys_database
    V1::Repository.create_api_auth_views
  end
  
  desc "Imports test API keys into auth token database"
  task :import_test_api_keys, [:owner] do |t, args|
    V1::Repository.import_test_api_keys(args.owner)
  end
  
  desc "Re-creates read-only CouchDB user and re-assigns roles"
  task :recreate_repo_users do
    V1::Repository.recreate_users
  end
  
  desc "Gets number of docs in repository"
  task :repo_doc_count do
    puts V1::Repository.doc_count
  end

  desc "Re-creates CouchDB database, users, river and re-populates Couch with test dataset"
  task :recreate_repo_env => :environment do
    V1::Repository.recreate_env(true)
  end

  desc "Gets number of docs in search index and repository"
  task :doc_counts do
    puts "Search docs    : #{ V1::SearchEngine.doc_count }"
    puts "Repo docs/views: #{ V1::Repository.doc_count }" 
  end

end
