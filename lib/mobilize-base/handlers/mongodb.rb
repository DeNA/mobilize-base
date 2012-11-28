module Mobilize
  class Mongodb

    def Mongodb.grid
      session = ::Mongoid.configure.sessions['default']
      database_name = session['database']
      host,port = session['hosts'].first.split(":")
      return ::Mongo::GridFileSystem.new(::Mongo::Connection.new(host,port).db(database_name))
    end

    def Mongodb.read_by_filename(filename)
      begin
        zs=Mongodb.grid.open(filename,'r').read
        return ::Zlib::Inflate.inflate(zs)
      rescue
        "failed Mongo read for filename #{filename}".oputs
        return nil
      end
    end

    def Mongodb.write_by_filename(filename,string)
      zs = ::Zlib::Deflate.deflate(string)
      Mongodb.grid.open(filename,'w',:delete_old => true){|f| f.write(zs)}
      return true
    end

    def Mongodb.delete_by_filename(filename)
      Mongodb.grid.delete(filename)
      return true
    end
  end
end
