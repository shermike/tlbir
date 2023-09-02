# frozen_string_literal: true

class Tlb
  attr_reader :types

  def initialize
    @types = {}
  end

  def get_type(type_name)
    return Type.new(type_name) if Type::PRIMITIVE_TYPES.include?(type_name)
    type = @types[type_name]
    raise "Undefined type: #{type}" unless type
    type
  end

  def get_or_create_type(type_name)
    @types[type_name] ||= Type.new(type_name)
  end

  def [](type)
    @types[type]
  end

  def dump(out=$stdout)
    out.write("TLB:\n")
    # @types.each { _2.dump('  ', out) }
    @types.each do |_, type|
      out.write("  type: #{type.name} #{type.params.map(&:to_s).join(' ')}\n")
      type.variants.each do |variant|
        variant.constraints.each do |constraint|
          out.write("    {#{constraint}}")
        end
        out.write("\n")
        max_len = variant.fields.map(&:name).max_by(&:size).size
        prefix = '    - '
        variant.fields.each do |field|
          out.write("#{prefix}#{field.name.ljust(max_len)} : #{field.value}\n")
          prefix = '      '
        end
      end
    end
  end
end

class Type
  attr_reader :name, :variants, :params

  PRIMITIVE_TYPES = %w[int uint]

  def initialize(name)
    @name = name
    @variants = []
    @params = []
  end

  def add_variant(variant)
    @variants << variant
  end

  def add_param(param)
    @params << param
  end

  def primitive?
    PRIMITIVE_TYPES.include?(name)
  end

  def [](variant)
    return @variants.find { _1.name == variant } if @variants.size > 1
    @variants[0][variant]
  end

  def instantiate(*args)
    raise "Wrong number of arguments" unless args.size == @params.size
    hargs = Hash[@params.zip(args)]
    type = Type.new(@name)
    @variants.each { type.add_variant(_1.instantiate(hargs)) }
    type
  end

  def dump(indent='', out=$stdout)
    out.write("#{indent}type: #{@name}\n")
    @variants.each { _1.dump(indent + '  ', out) }
  end
end

class Variant
  attr_reader :fields, :constraints
  attr_accessor :type

  def initialize
    @fields = []
    @type = ''
    @constraints = {}
  end

  def name
    constructor.name
  end

  def constructor
    @fields[0]
  end

  def add_field(field)
    @fields << field
  end

  def add_constraint(constraint)
    (@constraints[constraint.name] ||= []) << constraint
  end

  def find_field(name)
    @fields.find{ _1.name == name }
  end

  def create_field_ref(name)
    return nil unless field = find_field(name)
    FieldRef.new(field)
  end

  def [](field)
    find_field(field)
  end

  def instantiate(args)
    @fields.each do |field|
      field.fix_param_ref
    end
  end

  def dump(indent='', out=$stdout)
    out.write("#{indent}variant\n")
    @fields.each { _1.dump(indent + '  ', out) }
  end
end

class Field
  attr_reader :name
  attr_accessor :value

  def initialize(name, value=nil)
    @name = name
    @value = value
  end

  def dump(indent='', out=$stdout)
    out.write("#{indent}field #{@name}: #{value}\n")
  end

  def fix_param_ref(name, value)

  end

  def to_s
    "#{name}"
  end
end

class Value

  def fix_param_ref(name, value)
  end

end

class Number < Value
  attr_reader :bits

  def initialize(bits)
    if bits.is_a?(Constant)
      @bits = bits.value
    else
      @bits = bits
    end
  end

  def fix_param_ref(name, value)
    if @bits.is_a?(ParamRef)
      @bits = value
    elsif !bits.is_a?(Constant)
      bits.fix_param_ref(name, value)
    end
  end

  def to_s
    "Number #{@bits}"
  end
end

class Constant < Value
  attr_reader :value, :bits

  def initialize(value, bits=nil)
    @value = value
    @bits = bits || value.bit_length
  end

  def to_s
    "#{@value}"
  end
end

class TypeRef < Value
  attr_reader :type

  def initialize(type)
    @type = type
  end

  def to_s
    "TypeRef to #{@type.name}"
  end
end

class FieldRef < Value
  attr_reader :field

  def initialize(field)
    @field = field
  end

  def to_s
    "&#{@field.name}"
  end
end

class ParamRef < Value
  attr_reader :param

  def initialize(param)
    @param = param
  end

  def to_s
    "&#{@param}"
  end
end

class FieldExpression < Value
  attr_accessor :args

  def initialize(head, args = [])
    # unless head.is_a?(TypeRef) || head.is_a?(FieldRef) || head.is_a?(Constant)
    #   raise "Must be on of: TypeRef, FieldRef, Constant"
    # end
    @head = head
    @args = args
  end

  def optimize
    if @head.is_a?(Constant) && @args.size == 2 && @args[0].is_a?(ArithOperation) && @args[1].is_a?(Constant)
      return Constant.new(@args[0].eval(@head.value, @args[1].value))
    elsif @head.is_a?(TypeRef) && @head.type.primitive?
      raise "Expected one parameter for primitive type" unless @args.size == 1
      return Number.new(@args[0])
    end
    self
  end

  def fix_param_ref(name, value)

  end

  def to_s
    "(#{@head} #{@args.map(&:to_s).join(' ')})"
  end
end

class ArithOperation < Value

  OPERATIONS = [:add, :sub, :mul, :div]
  OPER_TO_NAME_MAP = {'+'=>:add, '-'=>:sub, '*'=>:mul, '/'=>:div}
  NAME_TO_OPER_MAP = {add: '+', sub: '-', mul: '*', div: '/'}

  def initialize(op)
    if op.is_a?(String)
      op = OPER_TO_NAME_MAP[op]
      raise "Invalid operation" unless op
    else
      raise "Invalid operation: #{op}" unless OPERATIONS.include?(op)
    end
    @op = op
  end

  def eval(a, b)
    a.send(NAME_TO_OPER_MAP[@op], b)
  end

  def to_s
    "#{NAME_TO_OPER_MAP[@op]}"
  end
end

class Constraint
  attr_reader :name

  def initialize(name)
    @name = name
  end
end

class TypeConstraint < Constraint
  attr_reader :type
  def initialize(name, type)
    super(name)
    @type = type
    puts self
  end

  def to_s
    "TypeConstraint: #{@name} #{@type}"
  end
end

class NumberConstraint < Constraint
  attr_reader :condition, :value

  CONDITIONS = [:gt, :ge, :lt, :le]
  COND_NAME_TO_OPER = {'>'=>:gt, '>='=>:ge, '<'=>:lt, '<='=>:le}
  COND_OPER_TO_NAME = {gt: '>', ge: '>=', lt: '<', le: '<='}

  def initialize(name, condition, value)
    if condition.is_a?(String)
      condition = string_to_condition(condition)
    else
      raise "Invalid condition: #{condition}" unless CONDITIONS.include?(condition)
    end
    super(name)
    @condition = condition
    @value = value
    puts self
  end

  def string_to_condition(condition)
    condition = COND_NAME_TO_OPER[condition]
    raise "Invalid condition: #{condition}" unless condition
    condition
  end

  def to_s
    name = " #{@name}" if @name
    "cnstr:#{name} #{COND_OPER_TO_NAME[@condition]} #{@value}"
  end
end
