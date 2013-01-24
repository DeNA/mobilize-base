module YAML
  def YAML.easy_load(string)
    begin
      YAML.load(s.param_string)
    rescue
      #replace colon w space colon, double space colons w single space
      gsub_colon_string = string.gsub(":",": ").gsub(":  ",": ")
      YAML.load("{#{gsub_colon_string}}")
    end
  end
end
