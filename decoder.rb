# frozen_string_literal: true

require_relative 'ir'

class Decoder
  def initialize(tlb, cell)
    @tlb = tlb
    @fields_map = {}
    @result = {}
    @current = @result
    @pos = 0
    @root_cell = cell
    @cell = @root_cell
  end

  def print(cell, type)
    if type.has_variants?
      variant = type.variants.find { _1.constructor == cell.data.data }
      pos = variant.constructor.bits
    else
      variant = type.variants.first
      pos = 0
    end
    raise "No variants match" unless variant

    variant.fields.each do |field|
      raise "Field must be a number" unless field.is_a?(Number)
      bits = resolve_field(field.bits)
      value = cell.data.bits.read_int(pos, bits)
      pos += bits
      @fields_map[field.name] = value
      puts "#{field.name}: #{value}"
    end
  end

  def assign_number(field)
    raise "Field must be a number" unless field.is_a?(Number)
    bits = resolve_field(field.bits)
    value = @cell.data.bits.read_int(@pos, bits)
    @current[field.name.to_sym] = value
    @pos += bits
  end

  def decode(type, args=[])
    type = type.instantiate(args)
    if type.has_variants?
      variant = type.variants.find { _1.constructor.value == @cell.data.bits.read_int(@pos, _1.constructor.bits) }
      raise "No variants found" unless variant
      @current[:cons] = variant.name
      @pos += variant.constructor.bits
      fields = variant.fields[1..-1]
    else
      variant = type.variants.first
      fields = variant.fields
    end
    raise "No variants match" unless variant

    fields.each do |field|
      case
      when field.is_a?(Number)
        assign_number(field)
      when field.is_a?(TypeRef)
        handle_type_ref(field)
      when field.is_a?(Expression)
        if field.type_ref?
          type = field.oper.type.instantiate(field.args)
          type_ref = TypeRef.new(type, field.oper.cell_ref)
          type_ref.name = field.name
          handle_type_ref(type_ref)
        # elsif field.oper.
        end
      else
        raise "Unexpected field type: #{field.class}"
      end
    end
    @result
  end

  def handle_type_ref(field)
    if field.ref?
      old_cell = @cell
      old_pos = @pos
      @cell = @cell.pop_cell
      @pos = 0
    end

    old = @current
    @current[field.name.to_sym] = {}
    @current = @current[field.name.to_sym]
    decode(field.type)
    @current = old
    if field.ref?
      @cell = old_cell
      @pos = old_pos
    end
  end

  def resolve_field(field)
    case
    when field.is_a?(Integer)
      value = field
    when field.is_a?(Constant)
      value = field.value
    when field.is_a?(FieldRef)
      value = @fields_map[field.field.name]
      raise "Unresolved field: #{field.field.name}, which is referenced by #{field.name}" if value.nil?
    when field.is_a?(Expression)
      value = evaluate_expression(field)
    else
      raise "Unsupported field type: #{field.class}"
    end
    # @fields_map[field.name] = value
    value
  end

  def evaluate_expression(field)
    raise "Must be ArithOperation" unless field.oper.is_a?(ArithOperation)
    args = field.args.map do |arg|
      case
      when arg.is_a?(Constant)
        arg.value
      when arg.is_a?(FieldRef)
        resolve_field_ref(arg)
      when field.is_a?(Expression)
        evaluate_expression(arg)
      else
        raise "Unsupported field type"
      end
    end
    field.oper.eval(*args)
  end

  def resolve_field_ref(field)
    raise "Must be FieldRef" unless field.is_a?(FieldRef)
    value = @fields_map[field.field.name]
    raise "Unresolved field: #{field.field.name}, which is referenced by #{field.name}" if value.nil?
    value
  end

end

