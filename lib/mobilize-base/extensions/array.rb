
class Array
  def sel(&blk)
    return self.select(&blk)
  end
  def group_count
    counts = Hash.new(0)
    self.each { |m| counts[m] += 1 }
    return counts
  end
  def sum
    return self.inject{|sum,x| sum + x }
  end
  def hash_array_to_tsv
    ha = self
    if ha.first.nil? or ha.first.class!=Hash
      return ""
    end
    max_row_length = ha.map{|h| h.keys.length}.max
    header_keys = ha.select{|h| h.keys.length==max_row_length}.first.keys
    header = header_keys.join("\t")
    rows = ha.map do |r|
      header_keys.map{|k| r[k]}.join("\t")
    end
    ([header] + rows).join("\n")
  end
end
