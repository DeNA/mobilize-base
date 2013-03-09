module Mobilize
  module Gridfs
    def Gridfs.config
      Base.config('gridfs')
    end

    def Gridfs.grid
      session = ::Mongoid.configure.sessions['default']
      database_name = session['database']
      host,port = session['hosts'].first.split(":")
      return ::Mongo::GridFileSystem.new(::Mongo::Connection.new(host,port).db(database_name))
    end

    def Gridfs.read_by_dataset_path(dst_path,user_name)
      begin
        zs=Gridfs.grid.open(dst_path,'r').read
        return ::Zlib::Inflate.inflate(zs)
      rescue
        return nil
      end
    end

    def Gridfs.write_by_dataset_path(dst_path,string,user_name)
      zs = ::Zlib::Deflate.deflate(string)
      raise "compressed string too large for Gridfs write" if zs.length > Gridfs.config['max_compressed_write_size']
      curr_zs = Gridfs.read_by_dataset_path(dst_path,user_name).to_s
      #write a new version when there is a change
      if curr_zs != zs
        Gridfs.grid.open(dst_path,'w',:versions => Gridfs.config['max_versions']){|f| f.write(zs)}
      end
      return true
    end

    def Gridfs.delete(dst_path)
      begin
        Gridfs.grid.delete(dst_path)
        return true
      rescue
        return nil
      end
    end
  end
end
