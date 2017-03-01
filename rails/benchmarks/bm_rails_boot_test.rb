# only run this benchmark with rails >= 5

require_relative 'support/benchmark_rails'

begin
  system("rails new my_app > /dev/null")

  Dir.chdir("my_app") do
    Benchmark.rails("rails_boot_test", time: 10) do
      system("DISABLE_SPRING=1 bin/rake test > /dev/null")
    end
  end
ensure
  system("rm -rf my_app")
end

