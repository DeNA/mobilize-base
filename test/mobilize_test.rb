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

    email = Mobilize::Gdrive.owner_email

    #kill all workers
    Mobilize::Jobtracker.kill_workers

    puts 'enqueue 4 workers on Resque, wait 20s'
    Mobilize::Jobtracker.prep_workers
    sleep 20
    assert Mobilize::Jobtracker.workers.length == Mobilize::Resque.config['max_workers'].to_i

    puts "create requestor 'mobilize'"
    requestor = Mobilize::Requestor.find_or_create_by_email(email)
    assert requestor.email == email

    puts "delete old books and datasets"
    # delete any old jobspec from previous test runs
    jobspec_title = requestor.jobspec_title
    books = Mobilize::Gbook.find_all_by_title(jobspec_title)
    books.each{|book| book.delete}

    puts "enqueue jobtracker, wait 45s"
    Mobilize::Jobtracker.start
    sleep 45
    puts "jobtracker status: #{Mobilize::Jobtracker.status}" 
    puts "status:#{Mobilize::Jobtracker.status}" #!= 'stopped'

    puts "requestor created jobspec?"
    books = Mobilize::Gbook.find_all_by_title(jobspec_title)
    assert books.length == 1

    puts "Jobtracker created jobspec with 'jobs' sheet?"
    jobs_sheets = Mobilize::Gsheet.find_all_by_name("#{jobspec_title}/Jobs",email)
    assert jobs_sheets.length == 1

    puts "add test_source data"

    test_source_rows = [
      ["test_header","test_header2","test_header3"],
      ["t1"]*3,
      ["t2"]*3
    ]

    book = books.first
    test_source_sheet = Mobilize::Gsheet.find_or_create_by_name("#{jobspec_title}/test_source",email)

    test_source_tsv = test_source_rows.map{|r| r.join("\t")}.join("\n")
    test_source_sheet.write(test_source_tsv)

    puts "add row to jobs sheet, wait 120s"

    jobs_sheet = jobs_sheets.first

    test_job_rows =    [{"name" => "test",
                       "active" => "true",
                     "schedule" => "once",
                       "status" => "",
                   "last_error" => "",
              "destination_url" => "",
                        "tasks" => "gsheet.read, gsheet.write",
                     "datasets" => "test_source",
                       "params" => "",
                  "destination" => "test_destination"},
                  #run after the first
                        {"name" => "test2",
                       "active" => "true",
                     "schedule" => "after test",
                       "status" => "",
                   "last_error" => "",
              "destination_url" => "",
                        "tasks" => "gsheet.read, gsheet.write",
                     "datasets" => "test_source",
                       "params" => "",
                  "destination" => "test_destination2"}
    ]

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
