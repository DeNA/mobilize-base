require 'test_helper'

describe "Mobilize" do

  def before
    puts 'before'

  end

  # enqueues 4 workers on Resque
  it "runs integration test" do
    email = Mobilize::Gdriver.owner_email

    #kill all workers
    Mobilize::Jobtracker.kill_workers

    puts 'enqueue 4 workers on Resque, wait 20s'
    Mobilize::Jobtracker.prep_workers
    sleep 20
    assert Mobilize::Jobtracker.workers.length == Mobilize::Resque.config['max_workers'].to_i

    #make sure old one is deleted
    Mobilize::Requestor.find_or_create_by_email(email).delete

    puts "create requestor 'mobilize'"
    requestor = Mobilize::Requestor.find_or_create_by_email(email)
    assert requestor.email == email

    puts "delete old books and datasets"
    # delete any old specbooks from previous test runs
    jobspec_title = requestor.jobspec_title
    books = Mobilize::Gbooker.find_all_by_title(jobspec_title)
    books.each{|book| book.delete}
    #delete old datasets for this specbook
    Mobilize::Dataset.all.select{|d| d.name.starts_with?(jobspec_title)}.each{|d| d.delete}

    puts "enqueue jobtracker, wait 60s"
    Mobilize::Jobtracker.start
    sleep 60
    puts "jobtracker status: #{Mobilize::Jobtracker.status}" 
    puts "status:#{Mobilize::Jobtracker.status}" #!= 'stopped'

    puts "requestor created specbook?"
    books = Mobilize::Gbooker.find_all_by_title(jobspec_title)
    assert books.length == 1

    puts "Jobtracker created jobspec with 'jobs' sheet?"
    jobs_sheets = Mobilize::Gsheeter.find_all_by_name("#{jobspec_title}/Jobs",email)
    assert jobs_sheets.length == 1

    puts "add test_source data"

    test_source_rows = [
      ["test_header","test_header2","test_header3"],
      ["t1"]*3,
      ["t2"]*3
    ]

    book = books.first
    test_source_sheet = Mobilize::Gsheeter.find_or_create_by_name("#{jobspec_title}/test_source",email)

    test_source_tsv = test_source_rows.map{|r| r.join("\t")}.join("\n")
    test_source_sheet.write(test_source_tsv)

    puts "add row to jobs sheet, wait 100s"

    #delete existing Jobs from the db
    Mobilize::Job.each{|j| j.delete}

    jobs_sheet = jobs_sheets.first

    test_job_rows =    [{"name" => "test",
                       "active" => "true",
                     "schedule" => "once",
                       "status" => "",
                   "last_error" => "",
                   "target_url" => "",
                 "read_handler" => "gsheeter",
                "write_handler" => "gsheeter",
                 "param_sheets" => "test_source",
                       "params" => "",
                       "target" => "test_target"},
                  #run after the first
                        {"name" => "test2",
                       "active" => "true",
                     "schedule" => "after test",
                       "status" => "",
                   "last_error" => "",
                   "target_url" => "",
                 "read_handler" => "gsheeter",
                "write_handler" => "gsheeter",
                 "param_sheets" => "test_source",
                       "params" => "",
                       "target" => "test_target2"}
    ]

    #update second row w details
    test_job_rows.each_with_index do |r,r_i|
      r.values.each_with_index do |v,v_i|
      jobs_sheet[r_i+2,v_i+1] = v
      end
    end

    jobs_sheet.save

    puts "job row added, force enqueued requestor"
    requestor.enqueue!
    sleep 100

    puts "jobtracker posted test sheet data to test target, and checksum succeeded?"
    test_target_sheet = Mobilize::Gsheeter.find_or_create_by_name("#{jobspec_title}/test_target",email)

    assert test_target_sheet.to_tsv == test_source_sheet.to_tsv
  end

  after do
    processes = `ps -A -o pid,command | grep [r]edis-test`.split($/)
    pids = processes.map { |process| process.split(" ")[0] }
    puts "Killing test redis server..."
    pids.each { |pid| Process.kill("TERM", pid.to_i) }
    puts "removing redis db dump file"
    sleep 5
    `rm -f #{$dir}/dump.rdb #{$dir}/dump-cluster.rdb`
  end
end
