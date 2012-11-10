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

    puts "delete old books"
    # delete any old specbooks from previous test runs
    jobspec_title = requestor.jobspec_title
    books = Mobilize::Gbooker.find_all_by_title(jobspec_title)
    books.each{|book| book.delete}

    puts "enqueue jobtracker"
    Mobilize::Jobtracker.start
    sleep 60
    puts "jobtracker status: #{Mobilize::Jobtracker.status}" 
    puts "status:#{Mobilize::Jobtracker.status}" #!= 'stopped'

    puts "requestor creates specbook"
    books = Mobilize::Gbooker.find_all_by_title(jobspec_title)
    puts "books:#{books.to_s}"
    #assert books.length == 1

    puts "Jobtracker creates jobspec with 'jobs' sheet with headers"
    jobs_sheets = Mobilize::Gsheeter.find_all_by_name("#{jobspec_title}/Jobs",email)


    puts "TODO: runs test job with test source gsheet"

    puts "TODO: verify that jobtracker posts tests source to test destination"

    # clean up
    Mobilize::Requestor.find_or_create_by_email(email).delete
  end

  after do
    processes = `ps -A -o pid,command | grep [r]edis-test`.split($/)
    pids = processes.map { |process| process.split(" ")[0] }
    puts "Killing test redis server..."
    pids.each { |pid| Process.kill("TERM", pid.to_i) }
    `rm -f #{$dir}/dump.rdb #{$dir}/dump-cluster.rdb`
  end
end
