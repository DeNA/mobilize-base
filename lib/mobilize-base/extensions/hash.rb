
class Hash
  #defined read and write methods for hashes to get around annoying mkpath issues
  def read_path(array)
    result=self
    array.each_with_index do |p,i|
      if result.class==Hash and result[p]
        result=result[p]
      elsif i==array.length-1
        return result[p]
      else
        return nil
      end
    end
    return result
  end
  #write array of arbitrary depth to the hash
  def write_path(array,data)
    return self[array.first.to_s]=data if array.length==1
    array.each_with_index do |m,i|
      arr_s = array[0..i]
      if !self.read_path(arr_s)
        eval(%{self["#{arr_s.join('"]["')}"]={}})
      elsif self.read_path(arr_s).class != Hash
        raise "There is data at #{arr_s.join("=>")}"
      end
    end
    eval(%{self["#{array[0..-2].join('"]["')}"]}).store(array[-1].to_s,data)
    return self
  end
  # BEGIN methods to create hash from XML
  class << self
    def from_xml(xml_io) 
      begin
        result = Nokogiri::XML(xml_io)
        return { result.root.name.to_sym => xml_node_to_hash(result.root)} 
      rescue Exception => e
        # raise your custom exception here
      end
    end 
    def xml_node_to_hash(node) 
      # If we are at the root of the document, start the hash 
      if node.element?
        result_hash = {}
        if node.attributes != {}
          result_hash[:attributes] = {}
          node.attributes.keys.each do |key|
            result_hash[:attributes][node.attributes[key].name.to_sym] = prepare(node.attributes[key].value)
          end
        end
        if node.children.size > 0
          node.children.each do |child| 
            result = xml_node_to_hash(child) 

            if child.name == "text"
              unless child.next_sibling || child.previous_sibling
                return prepare(result)
              end
            elsif result_hash[child.name.to_sym]
              if result_hash[child.name.to_sym].is_a?(Object::Array)
                result_hash[child.name.to_sym] << prepare(result)
              else
                result_hash[child.name.to_sym] = [result_hash[child.name.to_sym]] << prepare(result)
              end
            else 
              result_hash[child.name.to_sym] = prepare(result)
            end
          end

          return result_hash 
        else 
          return result_hash
        end 
      else 
        return prepare(node.content.to_s) 
      end 
    end          
    def prepare(data)
      (data.class == String && data.to_i.to_s == data) ? data.to_i : data
    end
  end
  def to_struct(struct_name)
    Struct.new(struct_name,*keys).new(*values)
  end
  # END methods to create hash from XML  
end
