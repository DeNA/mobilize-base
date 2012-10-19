class Mongoer

  def Mongoer.grid
    return Mongo::GridFileSystem.new(Mongoid.configure.sessions['default']['database'])
  end

  def Mongoer.read_by_filename(filename)
    begin
      zs=Mongoer.grid.open(filename,'r').read
      return Zlib::Inflate.inflate(zs)
    rescue
      "failed Mongo read for filename #{filename}".oputs
      return nil
    end
  end

  def Mongoer.write_by_filename(filename,string)
    zs = Zlib::Deflate.deflate(string)
    Mongoer.grid.open(filename,'w',:delete_old => true){|f| f.write(zs)}
    return true
  end

  def Mongoer.delete_by_filename(filename)
    Mongoer.grid.delete(filename)
    return true
  end

end
