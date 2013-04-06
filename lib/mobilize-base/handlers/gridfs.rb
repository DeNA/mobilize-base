require 'tempfile'
module Mobilize
  module Gridfs
    def Gridfs.config
      Base.config('gridfs')
    end

    def Gridfs.read_by_dataset_path(dst_path,*args)
      curr_file = Mongoid::GridFs::Fs::File.where(:filename=>dst_path).first
      zs = curr_file.data if curr_file
      return ::Zlib::Inflate.inflate(zs) if zs.to_s.length>0
    end

    def Gridfs.write_by_dataset_path(dst_path,string,*args)
      zs = ::Zlib::Deflate.deflate(string)
      raise "compressed string too large for Gridfs write" if zs.length > Gridfs.config['max_compressed_write_size']
      #find and delete existing file
      curr_file = Mongoid::GridFs::Fs::File.where(:filename=>dst_path).first
      curr_zs =  curr_file.data if curr_file
      #overwrite when there is a change
      if curr_zs != zs
        Mongoid::GridFs.delete(curr_file.id) if curr_file
        #create temp file w zstring
        temp_file = ::Tempfile.new("#{string}#{Time.now.to_f}".to_md5)
        temp_file.print(zs)
        temp_file.close
        #put data in file
        Mongoid::GridFs.put(temp_file.path,:filename=>dst_path)
      end
      return true
    end

    def Gridfs.delete(dst_path)
      curr_file = Mongoid::GridFs::Fs::File.where(:filename=>dst_path).first
      curr_file.delete
    end
  end
end
