module Mobilize
  class Dataset
    include Mongoid::Document
    include Mongoid::Timestamps
    field :handler, type: String
    field :path, type: String
    field :http_url, type: String
    field :raw_size, type: Fixnum
    field :last_cached_at, type: Time
    field :last_cache_handler, type: String
    field :last_read_at, type: Time
    field :cache_expire_at, type: Time

    index({ handler: 1, path: 1}, { unique: true})

    def url
      s = self
      "#{s.handler}://#{s.path}"
    end

    def read(user_name,*args)
      dst = self
      dst.update_attributes(:last_read_at=>Time.now.utc)
      "Mobilize::#{dst.handler.humanize}".constantize.read_by_dataset_path(dst.path,user_name,*args)
    end

    def write(string,user_name,*args)
      dst = self
      "Mobilize::#{dst.handler.humanize}".constantize.write_by_dataset_path(dst.path,string,user_name,*args)
      dst.raw_size = string.length
      dst.save!
      return true
    end

    def Dataset.find_by_url(url)
      handler,path = url.split("://")
      Dataset.find_by_handler_and_path(handler,path)
    end

    def Dataset.find_or_create_by_url(url)
      handler,path = url.split("://")
      Dataset.find_or_create_by_handler_and_path(handler,path)
    end

    def Dataset.find_by_handler_and_path(handler,path)
      Dataset.where(handler: handler, path: path).first
    end

    def Dataset.find_or_create_by_handler_and_path(handler,path)
      dst = Dataset.where(handler: handler, path: path).first
      dst = Dataset.create(handler: handler, path: path) unless dst
      return dst
    end

    def Dataset.read_by_url(url,user_name,*args)
      dst = Dataset.find_by_url(url)
      dst.read(user_name,*args) if dst
    end

    def Dataset.write_by_url(url,string,user_name,*args)
      dst = Dataset.find_or_create_by_url(url)
      dst.write(string,user_name,*args)
      url
    end
  end
end
