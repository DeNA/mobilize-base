class String
  def to_a
    return [self]
  end
  def oputs
    STDOUT.puts self
  end
  def eputs
    STDERR.puts self
  end
  def opp
    pp self
  end
  def bash(except=true)
    pid,stdin,stdout,stderr = Open4.popen4(self)
    pid,stdin = [nil,nil]
    raise stderr.read if (stderr.read.length>0 and except==true)
    return stdout.read
  end
  def escape_regex
    str = self
    new_str = str.clone
    char_string = "[\/^$. |?*+()"
    char_string.chars.to_a.each{|c|
    new_str.gsub!(c,"\\#{c}")}
    new_str
  end
  def gridsafe
    str = self
    str.downcase.gsub(/[^a-z0-9]/,"")
  end
  def googlesafe
    v=self
    return "" if v.to_s==""
    #normalize numbers by removing '$', '%', ',', ' '
    vnorm = v.to_s.norm_num
    vdigits = vnorm.split(".").last.length
    if vnorm.to_f.to_s=="Infinity"
      #do nothing
    elsif ("%.#{vdigits}f" % vnorm.to_f.to_s)==vnorm
      #round floats to 5 sig figs
      v=vnorm.to_f.round(5)
    elsif vnorm.to_i.to_s==vnorm
      #make sure integers are cast as such
      v=vnorm.to_i
    elsif v.is_time?
      begin
        time_vs = v.split("/")
        if time_vs.first.length<=2 and time_vs.second.length<=2
          #date is of the form mm/dd/yyyy or mm/dd/yy
          v=Time.parse("#{time_vs[2][0..3]}/#{time_vs[0]}/#{time_vs[1]}#{time_vs[2][4..-1]}")
        else
          v=Time.parse(v)
        end
      rescue
        #do nothing
      end
    end
    return v
  end
  def norm_num
    return self.gsub(",","").gsub("$","").gsub("%","").gsub(" ","")
  end
  def is_float?
    return self.norm_num.to_f.to_s == self.norm_num.to_s
  end
  def is_fixnum?
    return self.norm_num.to_i.to_s == self.norm_num.to_s
  end
  def is_time?
    if ((self.count("-")==2 or self.count("/")==2) and self.length>=8 and self.length<=20)
      return true
    end
    split_str = self.split(" ")
    if split_str.length==3 and
      split_str.first.count("-")==2 and
      split_str.last.first=="-" and
      split_str.second.count(":")==2
      return true
    end
  end
  def json_to_hash
    begin
      return JSON.parse(self)
    rescue => exc
      exc = nil
      return {}
    end
  end
  def tsv_to_hash_array
    rows = self.split("\n")
    return [] if rows.first.nil?
    return [{rows.first=>nil}] if (rows.length==2 and rows.second==nil)
    headers = rows.first.split("\t")
    if rows.length==1
      #return single member hash with all nil values
      return [headers.map{|k| {k=>nil}}.inject{|k,h| k.merge(h)}]
    end
    row_hash_arr =[]
    rows[1..-1].each do |row|
      cols = row.split("\t")
      row_hash = {}
      headers.each_with_index{|h,h_i| row_hash[h] = cols[h_i]}
      row_hash_arr << row_hash
    end
    return row_hash_arr
  end
end
