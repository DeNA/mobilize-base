#this module adds convenience methods to the Stage model
module Mobilize
  module StageHelper
    def idx
      s = self
      s.path.split("/").last.gsub("stage","").to_i
    end

    def out_dst
      #this gives a dataset that points to the output
      #allowing you to determine its size
      #before committing to a read or write
      s = self
      Dataset.find_by_url(s.response['out_url']) if s.response and s.response['out_url']
    end

    def err_dst
      #this gives a dataset that points to the output
      #allowing you to determine its size
      #before committing to a read or write
      s = self
      Dataset.find_by_url(s.response['err_url']) if s.response and s.response['err_url']
    end

    def params
      s = self
      p = YAML.easy_load(s.param_string)
      raise "Must resolve to Hash" unless p.class==Hash
      return p
    end

    def job
      s = self
      job_path = s.path.split("/")[0..-2].join("/")
      Job.where(:path=>job_path).first
    end
  end
end
