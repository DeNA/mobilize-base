module Mobilize
  class Gridfs

    def Gridfs.config
      Base.config('gridfs')[Base.env]
    end

    def Gridfs.grid
      session = ::Mongoid.configure.sessions['default']
      database_name = session['database']
      host,port = session['hosts'].first.split(":")
      return ::Mongo::GridFileSystem.new(::Mongo::Connection.new(host,port).db(database_name))
    end

    def Gridfs.read(path)
      begin
        zs=Gridfs.grid.open(path,'r').read
        return ::Zlib::Inflate.inflate(zs)
      rescue
        puts "failed Gridfs read for path #{path}"
        return nil
      end
    end

    def Gridfs.write(path,string)
      zs = ::Zlib::Deflate.deflate(string)
      raise "compressed string too large for Gridfs write" if zs.length > Gridfs.config['max_compressed_write_size']
      curr_zs = Gridfs.read(path).to_s
      #write a new version when there is a change
      if curr_zs != zs
        Gridfs.grid.open(path,'w',:versions => Gridfs.config['max_versions']){|f| f.write(zs)}
      end
      return true
    end

    def Gridfs.delete(path)
      begin
        Gridfs.grid.delete(path)
        return true
      rescue
        puts "failed Gridfs read for path #{path}"
        return nil
      end
    end
  end
end
