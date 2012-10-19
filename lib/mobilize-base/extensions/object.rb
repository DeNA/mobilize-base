class Object
  #alias for instance_eval
  def ie(&blk)
    self.instance_eval(&blk)
  end
end
