class Dataset
  include MongoMapper::Document
  safe
  key :requestor_id, String, :required => true
  key :handler, String, :required => true
  key :name, String, :required => true #path or _id to data
  key :url, String #url to retrieve data thru browser/scraper
  key :size, Fixnum
  key :last_cached_at, Time
  key :last_read_at, Time
  key :cache_expire_at, Time
  timestamps!

  before_destroy :destroy_cache

  def Dataset.add_indexes
    Dataset.ensure_index(:requestor_id)
    Dataset.ensure_index(:handler)
    Dataset.ensure_index(:name)
  end

  def read
    dst = self
    if dst.last_cached_at and (dst.cache_expire_at.nil? or dst.cache_expire_at > Time.now.utc)
      return dst.read_cache
    else
      return dst.handler.humanize.constantize.read_by_dst_id(dst.id.to_s)
    end
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
