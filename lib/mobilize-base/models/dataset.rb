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

    def read
      dst = self
      return "Mobilize::#{dst.handler.humanize}".constantize.read_by_path(dst.path)
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

    def Dataset.write_to_url(url,string)
      dst = Dataset.find_or_create_by_url(url)
      dst.write(string)
      url
    end

    def read
      dst = self
      dst.update_attributes(:last_read_at=>Time.now.utc)
      "Mobilize::#{dst.handler.humanize}".constantize.read_by_dataset_path(dst.path)
    end

    def write(string)
      dst = self
      "Mobilize::#{dst.handler.humanize}".constantize.write_by_dataset_path(dst.path,string)
      dst.raw_size = string.length
      dst.save!
      return true
    end

    def delete
      dst = self
      "Mobilize::#{dst.handler.humanize}".constantize.delete_by_dataset_path(dst.path)
      return true
    end
  end
end
