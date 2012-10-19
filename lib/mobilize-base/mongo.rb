require 'mongoid'
Mongoid.load!("#{Mobilize::Base.root_dir}mongoid.yml", :gem)
