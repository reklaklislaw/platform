require 'v1/searchable'

module V1

  module Item
    extend V1::Searchable
    
    def self.resource
      'item'
    end

  end

end
