class Dataset
  include Mongoid::Document
  include Mongoid::Timestamps
  field :requestor_id, type: String
  field :handler, type: String
  field :name, type: String
  field :url, type: String
  field :size, type: Fixnum
  field :last_cached_at, type: Time
  field :last_read_at, type: Time
  field :cache_expire_at, type: Time

  index({ requestor_id: 1})
  index({ handler: 1})
  index({ name: 1})

  before_destroy :destroy_cache

  def read
    dst = self
    if dst.last_cached_at and (dst.cache_expire_at.nil? or dst.cache_expire_at > Time.now.utc)
      return dst.read_cache
    else
      return dst.handler.humanize.constantize.read_by_dst_id(dst.id.to_s)
    end
  end

  def Dataset.find_by_handler_and_name(handler,name)
    Dataset.where(handler: handler, name: name).first
  end

  def Dataset.find_or_create_by_handler_and_name(handler,name)
    dst = Dataset.where(handler: handler, name: name).first
    dst = Dataset.create(handler: handler, name: name) unless dst
    return dst
  end

  def Dataset.find_or_create_by_requestor_id_and_handler_and_name(requestor_id,handler,name)
    dst = Dataset.where(requestor_id: requestor_id, handler: handler, name: name).first
    dst = Dataset.create(requestor_id: requestor_id, handler: handler, name: name) unless dst
    return dst
  end

  def write(data)
    dst = self
    dst.handler.humanize.constantize.write_by_dst_id(dst.id.to_s,data)
    dst.save!
    return true
  end

  def read_cache
    dst = self
    dst.update_attributes(:last_read_at=>Time.now.utc)
    return Mongoer.read_by_filename(self.id.to_s)
  end

  def write_cache(string,expire_at=nil)
    dst = self
    Mongoer.write_by_filename(dst.id.to_s,string)
    dst.update_attributes(:last_cached_at=>Time.now.utc,:cache_expire_at=>expire_at,:size=>string.length)
    return true
  end

  def delete_cache
    return Mongoer.delete_by_filename(dst.id.to_s)
  end

end
