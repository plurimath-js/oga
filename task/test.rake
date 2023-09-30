desc 'Runs the tests'
task :test => [:generate] do
  sh 'rspec spec --order random'
end

require 'opal/rspec/rake_task'
Opal::RSpec::RakeTask.new(:"test-opal")
