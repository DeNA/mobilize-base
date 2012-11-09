require 'test_helper'

describe "Mobilize" do

  def before
    puts 'before'

  end

  # enqueues 4 workers on Resque
  it "runs integration test" do
    email = Mobilize::Gdriver.owner_email

    puts 'enqueues 4 workers on Resque'
    Mobilize::Jobtracker.prep_workers
    sleep 10
    assert Mobilize::Jobtracker.workers.length == Mobilize::Resque.config['max_workers'].to_i
    puts "creates requestor 'mobilize'"

    requestor = Mobilize::Requestor.find_or_create_by_email(email)
    assert requestor.email == email

    puts "TODO: enqueues jobtracker" 

    puts "TODO: requestor creates specbook"

    puts "TODO: jobtracker creates jobspec with 'jobs' sheet with headers"

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
