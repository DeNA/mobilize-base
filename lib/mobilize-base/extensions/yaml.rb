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
        result_hash[k] = if v.class==String
                           v.gsub(": //","://")
                         elsif v.class==Array
                           v.map{|av| av.gsub(": //","://")}
                         else
                           v
                         end
      end
      return result_hash
    end
  end
end
