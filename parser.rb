# frozen_string_literal: true

require_relative 'ir'

class Parser
  attr_reader :types

  def initialize
    @data = nil
    @tlb = nil
    @variant = nil
    @pos = 0
    @types = {}
    @line = 0
  end

  def parse_file(filename)
    parse(File.read(filename))
  end

  def parse(data)
    @data = data

    @tlb = Tlb.new

    while !eof? do
      variant = read_definition()
      # type = @tlb.get_or_create_type(variant.type_name)
      # type.add_variant(variant)
      skip_chars(" \n")
    end

    @tlb
  end

  def read_definition
    skip_chars(" \n")
    @variant = Variant.new
    if ctor = read_constructor()
      @variant.add_field(ctor)
    end
    while true do
      skip_chars(" \n")
      case current_char
      when '{'
        @variant.add_constraint(read_constraint())
      when '='
        break
      else
        @variant.add_field(read_field())
      end
    end
    @variant.type = read_type()
    @variant.type.add_variant(@variant)
    @variant
  end

  def read_constructor
    name = read_token('#$ ', newline_is_error: true)
    bits = value = nil
    case current_char()
    when '#'
      advance_pos
      value = read_token(' ', newline_is_error: true)
      return nil if value == '_'
      value = Integer(value)
    when '$'
      advance_pos
      value = read_token(' ', newline_is_error: true)
      return nil if value == '_'
      bits = value.size
      value = value.to_i
    when ' '
      raise "Expected '_' constructor, but got '#{name}'" unless name == '_'
      advance_pos
      return nil
    end

    puts "New constructor: name=#{name}, value=#{value}, bits=#{bits}"
    Field.new(name, Constant.new(value, bits))
  end

  def read_constraint
    advance_pos
    name = read_token(':<>', newline_is_error: true)
    if current_char == ':'
      advance_pos
      type = read_token('}', newline_is_error: true, move_after_char: true)
      return TypeConstraint.new(name, type)
      end
    cond = read_chars('><=')
    advance_pos
    skip_spaces
    value = read_token('}', newline_is_error: true, move_after_char: true)
    return NumberConstraint.new(name, cond, Integer(value))
  end

  def read_field
    skip_chars(" \n")
    raise "Unexpected EOF" if eof?
    name = read_token(':')
    puts "New field: #{name}"
    field = Field.new(name)
    advance_pos
    field.value = read_field_expr()
    field
  end

  def try_integer(n)
    Integer(n)
  rescue ArgumentError, TypeError
    nil
  end

  def try_constant(s)
    begin
      return Constant.new(Integer(s))
    rescue ArgumentError, TypeError
      return nil
    end
  end

  def read_field_expr
    skip_spaces
    if current_char != '('
      token = read_token(' )')
      if m = /(uint|bits)(\d+)/.match(token)
        bits = m[2].to_i
        return Number.new(bits)
      elsif token =~ /[\+\-\*\/]/
        return ArithOperation.new(token)
      elsif value = try_constant(token)
        return value
      end
      return Number.new(32) if token == '#'
      return TypeRef.new(@tlb.get_type(token))
    end
    advance_pos
    token = read_token(' ')
    case token
    when '##'
      skip_spaces
      bits = read_token(')', move_after_char: true)
      return Number.new(bits.to_i)
    when '#<'
      skip_spaces
      token = read_token(')', move_after_char: true)
      if bits = try_integer(token)
        bits = (bits.to_i - 1).bit_length()
      else
        bits = FieldExpression.new(NumberConstraint.new(nil, '<', ParamRef.new(token)))
      end
      return Number.new(bits)
    when '#<='
      skip_spaces
      bits = read_token(')', move_after_char: true)
      return Number.new((bits.to_i).bit_length())
    # when /u?int/
    #   const = read_number_field
    #   Number.new(const)
    end

    head = try_constant(token)
    head ||= @variant.create_field_ref(token)
    head ||= TypeRef.new(@tlb.get_type(token))
    field = FieldExpression.new(head)

    while true do
      skip_spaces
      break if current_char == ')'
      field.args << read_field_expr()
    end
    advance_pos

    field.optimize
  end

  def read_number_field
    skip_spaces
    if current_char == '('
      main_token = read_token(' ')
      if number = try_constant(main_token)

      end

    end
  end

  def read_type
    skip_spaces
    expect_token('=')
    type_name = read_token(' ;', newline_is_error: true)
    raise "Invalid type name" unless type_name || type_name.empty?
    type = @tlb.get_or_create_type(type_name)
    if current_char != ';'
      while true do
        skip_spaces
        param = read_token(' ;', newline_is_error: true)
        type.add_param(param)
        break if current_char == ';' || eof?
      end
    end

    advance_pos
    type
  end

  def advance_pos(n = 1)
    @pos += n
  end

  def current_char
    @data[@pos]
  end

  def eof?
    @pos >= @data.size
  end

  def skip_chars(chars)
    while @pos < @data.size && chars.include?(current_char)
      @line += 1 if current_char == '\n'
      @pos += 1
    end
  end
  
  def skip_spaces
    skip_chars(' ')
  end

  def expect_token(token)
    raise "Expected sequence doesn't match': #{token}" if @data[@pos, token.size] != token
    @pos += token.size
    skip_spaces
  end

  def read_chars(chars)
    res = ''
    while chars.include?(current_char) do
      res += current_char
      advance_pos
      break if eof?
    end
    res
  end

  def read_token(until_chars, newline_is_error: false, move_after_char: false)
    stop_chars = until_chars + "\n"
    res = ''
    while @pos < @data.size && !stop_chars.include?(current_char)
      @line += 1 if current_char == '\n'
      res += current_char
      @pos += 1
    end
    raise "Read until failed - newline appeared before chars: #{until_chars}" if newline_is_error && current_char == "\n"
    @pos += 1 if move_after_char
    @line += 1 if current_char == '\n'
    res
  end
end
