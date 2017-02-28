#
# Bundler Benchmark driver
#
require 'net/http'
require 'json'
require 'pathname'
require 'optparse'
require 'digest'
require 'benchmark'
require 'benchmark/ips'
require 'fileutils'

RAW_URL = 'https://raw.githubusercontent.com/ruby-bench/ruby-bench-suite/master/rails/benchmarks/'

class BenchmarkDriver
  def self.benchmark(options)
    self.new(options).run
  end

  def initialize(options)
    @repeat_count = options[:repeat_count]
    @local = options[:local]
    @versions = options[:versions]
  end

  def run
    versions_to_run = @versions || %w(4.2.8 5.0.0.1 5.0.1)
    versions_to_run.each do |version|
      run_single(version)
    end
  end

  private

  def files
    Pathname.glob("#{File.expand_path(File.dirname(__FILE__))}/bm_*")
  end

   def run_single(version)
    system('gem uninstall rails --all --force')
    system('gem uninstall activesupport --all --force')
    system("gem install rails:#{version} --no-doc")
    system("rails _#{version}_ new my_app_#{version}")

    scripts = {
      '4' => [
        'bin/rake environment'
      ],
      '5' => [
        'bin/rails test',
        'bin/rake environment'
      ]
    }

    Dir.chdir("my_app_#{version}") do
      scripts[version[0]].each do |script|
        output = measure(script, version)
        return unless output

        request = Net::HTTP::Post.new('/benchmark_runs')
        request.basic_auth(ENV["API_NAME"], ENV["API_PASSWORD"])

        submit = {
          'benchmark_type[category]' => output["label"],
          'benchmark_type[script_url]' => "#{RAW_URL}#{version}",
          'benchmark_type[digest]' => Digest::SHA2.hexdigest(version),
          'benchmark_run[environment]' => "#{`ruby -v; gem -v`.strip}",
          'repo' => 'bundler',
          'organization' => ENV['ORGANIZATION']
        }

        request.set_form_data(submit.merge(
          {
            "benchmark_run[result][iterations_per_second]" => output[:iterations_per_second].round(3),
            'benchmark_result_type[name]' => 'Number of iterations per second',
            'benchmark_result_type[unit]' => 'Iterations per second'
          }
        ))

        endpoint.request(request) unless @local

        request.set_form_data(submit.merge(
          {
            "benchmark_run[result][total_allocated_objects_per_iteration]" => output["total_allocated_objects_per_iteration"],
            'benchmark_result_type[name]' => 'Allocated objects',
            'benchmark_result_type[unit]' => 'Objects'
          }
        ))

        if @local
          puts output
        else
          endpoint.request(request)
          puts "Posting results to Web UI...."
        end
      end
    end
  ensure
    FileUtils.rm_rf("my_app_#{version}")
  end

  def endpoint
    @endpoint ||= begin
      http = Net::HTTP.new(ENV["API_URL"] || 'rubybench.org', 443)
      http.use_ssl = true
      http
    end
  end

  def measure(script, version)
    results = []
    @repeat_count.times do
      report = Benchmark.ips do |x|
        x.report("v: #{version} script: #{script}") { `DISABLE_SPRING=1 #{script}` }
      end

      entry = report.entries.first
      output = {
        label: script,
        version: version.to_s,
        iterations_per_second: entry.ips
      }

      puts "#{output["label"]} #{output["iterations_per_second"]}/ips"
      results << output
    end

    results.sort_by do |result|
      result['iterations_per_second']
    end.last
  end
end

options = {
  repeat_count: 5,
  pattern: [],
  local: false,
}

OptionParser.new do |opts|
  opts.banner = "Usage: ruby driver.rb [options]"

  opts.on("-r", "--repeat-count [NUM]", "Run benchmarks [NUM] times taking the best result") do |value|
    options[:repeat_count] = value.to_i
  end

  opts.on("-v", "--versions <PATTERN1,PATTERN2,PATTERN3>", "Benchmark specific versions") do |value|
    options[:versions] = value.split(',').map(&:strip)
  end

  opts.on("--local", "Don't report benchmark results to the server") do |value|
    options[:local] = value
  end
end.parse!(ARGV)

BenchmarkDriver.benchmark(options)
