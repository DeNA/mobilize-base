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

    puts 'enqueue 4 workers on Resque'
    Mobilize::Jobtracker.prep_workers
    sleep 20
    assert Mobilize::Jobtracker.workers.length == Mobilize::Resque.config['max_workers'].to_i

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

    puts "enqueue jobtracker"
    Mobilize::Jobtracker.start
    sleep 60
    puts "jobtracker status: #{Mobilize::Jobtracker.status}" 
    puts "status:#{Mobilize::Jobtracker.status}" #!= 'stopped'

    puts "requestor creates specbook"
    books = Mobilize::Gbooker.find_all_by_title(jobspec_title)
    assert books.length == 1

    puts "Jobtracker creates jobspec with 'jobs' sheet with headers"
    jobs_sheets = Mobilize::Gsheeter.find_all_by_name("#{jobspec_title}/Jobs",email)
    assert jobs_sheets.length == 1

    puts "add test_source data incl blank column"

    test_source_rows = [
      ["test_header","test_header2","test_header3","","skip_header1","skip_header2"],
      ["t1"]*6,
      ["t2"]*6
    ]

    book = books.first
    test_source_sheet = Mobilize::Gsheeter.find_or_create_by_name("#{jobspec_title}/test_source",email)

    test_source_tsv = test_source_rows.map{|r| r.join("\t")}.join("\n")
    test_source_sheet.write(test_source_tsv)

    puts "add row to jobs sheet"

    jobs_sheet = jobs_sheets.first

    test_job_row =    {"name" => "test",
                     "active" => "true",
                   "schedule" => "once",
                     "status" => "",
                 "last_error" => "",
            "destination_url" => "",
               "read_handler" => "gsheet",
              "write_handler" => "gsheet",
               "param_source" => "test_source",
                     "params" => "",
                "destination" => "test_destination"}

    #update second row w details
    test_job_row.values.each_with_index do |v,v_i|
      jobs_sheet[2,v_i+1] = v
    end

    jobs_sheet.save

    puts "verify that jobtracker posts tests source to test destination"


    # clean up
    Mobilize::Requestor.find_or_create_by_email(email).delete
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
