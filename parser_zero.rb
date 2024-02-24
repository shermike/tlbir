# frozen_string_literal: true

require_relative 'ir'
require 'ostruct'

class Parser
  attr_reader :types

  def initialize
    @data = nil
    @tlb = nil
    @variant = nil
    @pos = 0
    @types = {}
    @line = 1
    @verbose = false
  end
  
  def log(msg)
    puts(msg) if @verbose
  end

  def parse_file(filename)
    parse(File.read(filename))
  end

  def parse(data)
    @data = data

    @tlb = Tlb.new

    begin
      while !eof? do
        read_definition()
      end
    rescue => e
      raise e.exception("Error at #{@line} line: #{e}")
      # raise "Error at #{@line} line: #{e}"
    end

    @tlb
  end

  def read_definition
    skip_chars(" \n")
    @variant = Variant.new
    if ctor = read_constructor()
      @variant.add_field(ctor)
    end
    return if eof?
    while true do
      skip_chars(" \n")
      case current_char
      when '{'
        @variant.add_constraint(read_constraint())
      when '='
        break
      when nil
        break
      else
        field = read_field()
        @variant.add_field(field) if field
      end
    end
    @variant.type = read_type()
    @variant.type.add_variant(@variant)
    # @variant.type.verify
  end

  def read_constructor
    name = read_token('#$ ', newline_is_error: true)
    return nil if eof?
    bits = value = nil
    log "New variant: #{name}"
    case current_char()
    when '#'
      advance_pos
      value = read_token(' ', newline_is_error: false)
      return nil if value == '_'
      value = Integer(value, 16)
    when '$'
      advance_pos
      value = read_token(' ', newline_is_error: false)
      return nil if value == '_'
      bits = value.size
      value = value.to_i(2)
    when ' '
      # raise "Expected '_' constructor, but got '#{name}'" unless name == '_'
      advance_pos
      return nil
    end

    log "Constructor: name=#{name}, value=#{value}, bits=#{bits}"
    res = Constant.new(value, bits)
    res.name = name
    res
  end

  def read_constraint
    advance_pos
    name = read_token(':<>=', newline_is_error: true)
    if current_char == ':'
      advance_pos
      type = read_token('}', newline_is_error: true, move_after_char: true)
      return TypeConstraint.new(name, type)
      end
    cond = read_chars('><=')
    advance_pos
    skip_spaces
    value = read_token('}', newline_is_error: true, move_after_char: true)
    return Constraint.new(name)
  end

  def read_field
    skip_chars(" \n")
    if eof?
      raise "Unexpected EOF"
    end
    field = OpenStruct.new
    field.name = read_token('(: ')
    if field.name == '^[' || field.name == ']'
      advance_pos
      return nil
    end
    if current_char == '('
      field.name = "_" if field.name.empty?
      field.value = read_type_str()
    elsif current_char == ' '
      field.value = field.name
      field.name = "_"
    else
      unless current_char == ':'
        raise "Expected ':' while reading field name, got: #{current_char}"
      end
      advance_pos
      field.value = read_type_str()
    end
    field
    # field = read_field_expr()
    # field.name = name

  end

  def read_type_str
    s = ""
    paren_num = 0
    while true do
      t = read_token(' ()')
      s += t
      case current_char
      when "\n"
        break if paren_num == 0
      when ' '
        break if paren_num == 0
      when '('
        paren_num += 1
      when ')'
        paren_num -= 1
      end
      s += current_char
      advance_pos
    end
    s
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
    is_ref = current_char == '^'
    advance_pos if is_ref

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
      field = @tlb.try_create_type_ref(token, is_ref)
      field ||= @variant.add_maybe_param_ref(token)
      # return Expression.new(field)
      return field
    end
    advance_pos
    token = read_token(' ')
    case token
    when '##'
      skip_spaces
      token = read_token(')', move_after_char: true)
      bits = try_integer(token)
      bits ||= ParamRef.new(token)
      return Number.new(bits)
    when '#<'
      skip_spaces
      token = read_token(')', move_after_char: true)
      if bits = try_integer(token)
        bits = (bits.to_i - 1).bit_length()
      else
        bits = Expression.new(ArithOperation.new('<'), [ParamRef.new(token)])
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

    oper = try_constant(token)
    oper ||= @variant.create_field_ref(token)
    oper ||= TypeRef.new(@tlb.get_type(token), is_ref)
    field = Expression.new(oper)

    while true do
      skip_spaces
      break if current_char == ')'
      field.args << read_field_expr()
    end
    advance_pos

    field.fix_operands_order
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
        @variant.add_param(param)
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
      next_line if current_char == "\n"
      @pos += 1
    end
    while @data[@pos] == '/' && @data[@pos + 1] == '/'
      advance_pos(2)
      read_token('', move_after_char: true)
      skip_chars(chars)
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
    while !eof? && !stop_chars.include?(current_char)
      if @data[@pos] == '/' && @data[@pos + 1] == '/'
        skip_chars('/')
        raise "Wrong comment" unless res.empty?
        read_token('', move_after_char: true)
        skip_spaces
        next
      end
      res += current_char
      @pos += 1
    end
    raise "Read until failed - newline appeared before chars: #{until_chars}" if newline_is_error && current_char == "\n"

    log "Read token #{res}"
    next_line if current_char == "\n"
    @pos += 1 if move_after_char
    res
  end

  def next_line
    if @last_new_line == @pos
      return
    end
    @last_new_line = @pos
    @line += 1
    log "LINE: #{@line}"
  end
end
