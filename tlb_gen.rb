# frozen_string_literal: true

require 'optparse'
require 'ostruct'
require_relative 'parser'


def options
  return @options if @options
  @options = OpenStruct.new
  OptionParser.new do |opts|
    opts.banner = 'Usage: tlb_gen.rb [options]'
    opts.on('-v', '--verbose', 'Verbose logging')
  end.parse!(into: @options)
  @options.input = ARGV.pop
  abort('Positional argument is required: tlb scheme') unless @options.input
  @options
end

def main
  Parser.new(options.input).parse
end

main
