module Mobilize
  class Dataset
    include Mongoid::Document
    include Mongoid::Timestamps
    field :handler, type: String
    field :path, type: String
    field :url, type: String
    field :raw_size, type: Fixnum
    field :last_cached_at, type: Time
    field :last_cache_handler, type: String
    field :last_read_at, type: Time
    field :cache_expire_at, type: Time

    index({ handler: 1, path: 1}, { unique: true})

    def read
      dst = self
      return dst.handler.humanize.constantize.read_by_path(dst.path)
    end

    def Dataset.find_by_handler_and_path(handler,path)
      Dataset.where(handler: handler, path: path).first
    end

    def Dataset.find_or_create_by_handler_and_path(handler,path)
      dst = Dataset.where(handler: handler, path: path).first
      dst = Dataset.create(handler: handler, path: path) unless dst
      return dst
    end

    def write(string)
      dst = self
      dst.handler.humanize.constantize.write_by_path(dst.path,string)
      dst.raw_size = string.length
      dst.save!
      return true
    end

    def cache_valid?
      return true if dst.last_cached_at and (dst.cache_expire_at.nil? or dst.cache_expire_at > Time.now.utc)
    end

    def read_cache(cache_handler="gridfs")
      dst = self
      if cache_valid?
        dst.update_attributes(:last_read_at=>Time.now.utc)
        return cache_handler.humanize.constantize.read([dst.handler,dst.path].join("://"))
      else
        raise "Cache invalid or not found for #{cache_handler}://#{dst.path}"
      end
    end

    def write_cache(string,expire_at=nil,cache_handler="gridfs")
      dst = self
      cache_handler.humanize.constantize.write([dst.handler,dst.path].join("://"),string)
      dst.update_attributes(:last_cached_at=>Time.now.utc,
                            :last_cache_handler=>cache_handler.to_s.downcase,
                            :cache_expire_at=>expire_at,
                            :size=>string.length)
      return true
    end

    def delete_cache(cache_handler="gridfs")
      return cache_handler.humanize.constantize.delete(dst.handler, dst.path)
    end
  end
end
