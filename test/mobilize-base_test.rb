require 'test_helper'

describe "Mobilize" do

  def before
    puts 'nothing before'
  end

  # enqueues 4 workers on Resque
  it "runs integration test" do

    puts "restart test redis"
    Mobilize::Jobtracker.restart_test_redis

    puts "clear out test db"
    Mobilize::Jobtracker.drop_test_db

    puts "build test jobspec"
    email = Mobilize::Gdrive.owner_email
    puts "create requestor 'mobilize'"
    requestor = Mobilize::Requestor.find_or_create_by_email(email)
    assert requestor.email == email    

    Mobilize::Jobtracker.build_test_jobspec(requestor.id.to_s) 
    assert Mobilize::Jobtracker.workers.length == Mobilize::Resque.config['max_workers'].to_i

    jobspec_title = requestor.jobspec_title

    puts "requestor created jobspec?"
    books = Mobilize::Gbook.find_all_by_title(jobspec_title)
    assert books.length == 1
    
    puts "Jobtracker created jobspec with 'jobs' sheet?"
    jobs_sheets = Mobilize::Gsheet.find_all_by_name("#{jobspec_title}/Jobs",email)
    assert jobs_sheets.length == 1

    puts "add test_source data"    
    book = books.first
    test_source_sheet = Mobilize::Gsheet.find_or_create_by_name("#{jobspec_title}/test_source",email)

    test_source_tsv = ::YAML.load_file("#{Mobilize::Base.root}/test/test_source_rows.yml").hash_array_to_tsv
    test_source_sheet.write(test_source_tsv)

    puts "add row to jobs sheet, wait 120s"
    jobs_sheet = jobs_sheets.first

    test_job_rows = ::YAML.load_file("#{Mobilize::Base.root}/test/base_job_rows.yml")
    jobs_sheet.add_or_update_rows(test_job_rows)

    puts "job row added, force enqueued requestor"
    requestor.enqueue!
    sleep 120

    puts "jobtracker posted test sheet data to test destination, and checksum succeeded?"
    test_destination_sheet = Mobilize::Gsheet.find_or_create_by_name("#{jobspec_title}/test_destination",email)

    assert test_destination_sheet.to_tsv == test_source_sheet.to_tsv

    puts "stop test redis"
    Mobilize::Jobtracker.stop_test_redis
  end

end
