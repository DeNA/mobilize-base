
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
    if self.first.nil? or self.first.class!=Hash
      return ""
    end
    header = self.first.keys.join("\t")
    rows = self.map{|r| r.values.join("\t")}
    ([header] + rows).join("\n")
  end
end
