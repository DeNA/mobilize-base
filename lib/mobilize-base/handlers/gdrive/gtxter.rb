class Gtxter

  def Gtxter.post_by_job_id(job_id)
    #posts a file to the mobilize account,
    #posts the time and link to given cells
    j=job_id.j
    r=j.requestor
    title = %{#{r.name}_#{j.destination}}
    gztitle = [title,".gz"].join if !title.ends_with?(".gz")
    post_dst = Dataset.find_or_create_by_handler_and_name_and_requestor_id('gtxter',gztitle,r.id.to_s)
    tsv = j.prior_task['output_dst_id'].dst.read.gsub("#","\t")
    account = Gdriver.get_worker_account
    #return false if there are no accounts available
    return false unless account
    Jobtracker.set_worker_args(j.worker_key,{"account"=>account})
    gzfile = Gtxter.post_by_gztitle(gztitle,tsv,account)
    post_dst.update_attributes(:url=>gzfile.human_url)
    #write
    return true
  end

  def Gtxter.post_by_gztitle(gztitle,tsv,account=nil)
    #expects a tsv, and a gz-suffixed file.
    #Gzips the tsv, uploads to gz-suffixed file on gdocs
    upload_file = %{#{Rails.root}/tmp/#{gztitle}_upload.txt}
    File.open(upload_file,"w") {|f| f.print(tsv)}
    upload_filegz = upload_file + ".gz"
    #delete the upload file if already exists, gzip tsv one
    "rm -f #{upload_filegz};gzip #{upload_file}".bash
    old_rfile = Gdriver.txts.select{|t| t.title==gztitle}.first
    old_rfile.delete unless old_rfile.nil?
    #use base mobilize to ensure proper ownership
    rfile = Gdriver.root.upload_from_file(upload_filegz,gztitle, :convert=>false)
    "Posted file #{gztitle} at #{Time.now.utc.to_s}".oputs
    #add only workers - can't get file acl to work as expected
    Gfiler.add_worker_acl_by_title(gztitle)
    return rfile
  end
end

