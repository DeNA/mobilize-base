module YAML
  def YAML.easy_load(string)
    begin
      return YAML.load(s.param_string)
    rescue
      #replace colon w space colon, double space colons w single space
      gsub_colon_string = string.gsub(":",": ").gsub(":  ",": ")
      easy_hash = YAML.load("{#{gsub_colon_string}}")
      #make sure urls have their colon spaces fixed
      result_hash={}
      easy_hash.each do |k,v|
        result_hash[k] = v.gsub(": //","://")
      end
      return result_hash
    end
  end
end
