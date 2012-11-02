require 'test_helper'
describe "Mobilize" do
  before do
    puts "before"
  end

  it "preps 4 workers on Jobtracker" do
    Mobilize::Jobtracker.prep_workers
    sleep 10
    assert Mobilize::Jobtracker.workers.length == Mobilize::Resque.config['max_workers'].to_i
  end

  after do
    processes = `ps -A -o pid,command | grep [r]edis-test`.split($/)
    pids = processes.map { |process| process.split(" ")[0] }
    puts "Killing test redis server..."
    pids.each { |pid| Process.kill("TERM", pid.to_i) }
    `rm -f #{$dir}/dump.rdb #{$dir}/dump-cluster.rdb`
  end

end
