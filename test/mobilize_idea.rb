require 'test_helper'

class MiniTestWithHooks::Unit < MiniTest::Unit
  def before_suites
      puts 'before'
      # start redis
  end

  def after_suites
      # teardown redis
      puts 'after'
  end

  def _run_suites(suites,type)
    begin
      before_suites
      super(suites,type)
    ensure
      after_suites
    end
  end
  def _run_suite(suite,type)
    begin
      suite.before_suite
      super(suite, type)
    ensure
      suite.after_suite
    end
  end
end

module MiniTestWithTransactions
  class Unit < MiniTestWithHooks::Unit
    include TestSetupHelper

    def before_suites
      super
    end

    def after_suites
      super
    end
  end
end


MiniTest::Unit.runner = MiniTestWithTransactions::Unit.new

describe "Mobilize" do

  it "enqueues 4 workers on Resque" do
    Mobilize::Jobtracker.prep_workers
    sleep 10
    assert Mobilize::Jobtracker.workers.length == Mobilize::Resque.config['max_workers'].to_i
  end

  it "creates requestor 'mobilize'" do
    email = Mobilize::GDriver.owner_email
    requestor = Mobilize::Requestor.find_or_create_by_email(email)
    assert requestor.email == email
    # clean up
    requestor.delete
  end

  it "enqueues jobtracker" do
    # TODO implement this test!
  end

  it "requestor creates specbook" do
    # TODO implement this test!
  end

  it "jobtracker creates jobspec with 'jobs' sheet with headers" do
    # TODO implement this test!
  end

  it "runs test job with test source gsheet" do
    # TODO implement this test!
  end

  it "verify that jobtracker posts tests source to test destination" do
    # TODO implement this test!
  end

  after do
    processes = `ps -A -o pid,command | grep [r]edis-test`.split($/)
    pids = processes.map { |process| process.split(" ")[0] }
    puts "Killing test redis server..."
    pids.each { |pid| Process.kill("TERM", pid.to_i) }
    `rm -f #{$dir}/dump.rdb #{$dir}/dump-cluster.rdb`
  end
end
