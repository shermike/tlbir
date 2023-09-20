# frozen_string_literal: true

class Tlb
  attr_reader :types

  def initialize
    @types = {}
  end

  def get_type(type_name)
    return Type.new(type_name) if Type::PRIMITIVE_TYPES.include?(type_name)
    type = @types[type_name]
    raise "Undefined type: #{type_name}" unless type
    type
  end

  def add_type(type_name, type)
    raise "Type already exists: #{type_name}" if @types.include?(type_name)
    @types[type_name] = type
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
      out.write("  type: #{type.name} #{type.variants[0].params.map(&:to_s).join(' ')}\n")
      type.variants.each do |variant|
        variant.constraints.each do |constraint|
          out.write("    {#{constraint}}")
        end
        out.write("\n") unless variant.constraints.empty?
        max_len = variant.fields.map(&:name).max_by(&:size).size
        prefix = '    - '
        variant.fields.each do |field|
          out.write("#{prefix}#{field.name.ljust(max_len)} : #{field}\n")
          prefix = '      '
        end
      end
    end
  end
end

########################################################################################################################
# Type
#
class Type
  attr_reader :name, :variants

  PRIMITIVE_TYPES = %w[int uint]

  def initialize(name)
    @name = name
    @variants = []
  end

  def add_variant(variant)
    @variants << variant
  end

  def primitive?
    PRIMITIVE_TYPES.include?(name)
  end

  def [](variant)
    return @variants[variant] if variant.is_a?(Integer)
    @variants.find { _1.name == variant }
  end

  def instantiate(args)
    # hargs = Hash[@params.zip(args)]
    # type = self.clone #Type.new(@name)
    args.map! { _1.is_a?(Integer) ? Constant.new(_1) : TypeRef.new(_1) }
    type = Marshal.load(Marshal.dump(self))
    type.variants.each { _1.instantiate(args) }
    type
  end

  def has_variants?
    @variants.size > 1
  end

  def verify
    raise "Empty type is not allowed" if @variants.empty?
    args_num = @variants[0].params.count
    raise "Wrong number of arguments" unless @variants.all? { _1.params.count == args_num}
    if @variants[0].fields.first.is_a?(Constant)
      raise "All variants must have first field as Constant" unless @variants.all? { _1.fields.first.is_a?(Constant) }
    end
  end

  def dump(indent='', out=$stdout)
    out.write("#{indent}type: #{@name}\n")
    @variants.each { _1.dump(indent + '  ', out) }
  end
end
########################################################################################################################
# Variant
#
class Variant
  attr_reader :fields, :constraints, :params
  attr_accessor :type

  def initialize
    @fields = []
    @type = ''
    @constraints = {}
    @params = []
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

  def add_param(param)
    @params << param
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
    hargs = Hash[@params.zip(args)]
    @fields.each do |field|
      field.fix_param_ref(hargs)
      field.optimize
    end
  end

  def dump(indent='', out=$stdout)
    out.write("#{indent}variant\n")
    @fields.each { _1.dump(indent + '  ', out) }
  end
end

########################################################################################################################
# Fields
#
class Field
  attr_accessor :name

  def initialize(name)
    @name = name
  end

  def dump(indent='', out=$stdout)
    out.write("#{indent}field #{@name}: #{self.to_s}\n")
  end

  def fix_param_ref(hargs)
  end

  def optimize
  end
end

class Number < Field
  attr_reader :bits

  def initialize(bits)
    if bits.is_a?(Constant)
      @bits = bits.value
    else
      @bits = bits
    end
  end

  def fix_param_ref(hargs)
    if @bits.is_a?(ParamRef)
      @bits = hargs[@bits.param]
      raise "Parameter must be an integer" unless @bits.is_a?(int)
    end
    @bits.fix_param_ref(hargs)
  end

  def optimize
    @bits = @bits.optimize if @bits.is_a?(Expression)
  end

  def to_s
    "Number #{@bits}"
  end
end

class Constant < Field
  attr_reader :value, :bits

  def initialize(value, bits=nil)
    @value = value
    @bits = bits || value.bit_length
  end

  def ==(other)
    case
    when other.is_a?(BitArray)
      return @value == other.read_int(0, @bits)
    else
      raise "Unsupported type: #{other.class}"
    end
  end

  def to_s
    ":#{@value}"
  end
end

class TypeRef < Field
  attr_reader :type, :cell_ref

  def initialize(type, cell_ref)
    @type = type
    @cell_ref = cell_ref
  end

  def to_s
    "TypeRef<#{@type.name}>"
  end
end

class FieldRef < Field
  attr_reader :field

  def initialize(field)
    @field = field
  end

  def to_s
    "&#{@field.name}"
  end
end

class ParamRef < Field
  attr_reader :param

  def initialize(param)
    @param = param
  end

  def to_s
    "&#{@param}"
  end

  def fix_param_ref(hargs)
    raise "fix_param_ref must not reach ParamRef object"
  end
end

class Expression < Field
  attr_accessor :args, :oper

  def initialize(oper, args=[])
    # unless oper.is_a?(TypeRef) || oper.is_a?(FieldRef) || oper.is_a?(Constant)
    #   raise "Must be on of: TypeRef, FieldRef, Constant"
    # end
    @oper = oper
    @args = args
  end

  def type_ref?
    @oper.is_a?(TypeRef)
  end

  def arith?
    @oper.is_a?(ArithOperation)
  end

  def fix_operands_order
    oper_idx = @args.find_index { _1.is_a?(ArithOperation) }
    if oper_idx
      raise "Invalid experssion" if arith?
      @oper, @args[oper_idx] = @args[oper_idx], @oper
    end
  end

  def optimize
    if arith? && @args.size == 2 && @args[0].is_a?(Constant) && @args[1].is_a?(Constant)
      return Constant.new(@oper.eval(@args[0].value, @args[1].value))
    elsif type_ref? && @oper.type.primitive?
      raise "Expected one parameter for primitive type" unless @args.size == 1
      return Number.new(@args[0])
    elsif arith? && @oper.conditional? && @args[0].is_a?(Constant)
      value = @args[0].value
      value -= 1 if @oper.op == :lt
      return Constant.new(value.bit_length)
    end
    self
  end

  def fix_param_ref(hargs)
    if @oper.is_a?(ParamRef)
      @oper = hargs[@oper.param]
    else
      @oper.fix_param_ref(hargs)
    end
    @args.map! do |arg|
      if arg.is_a?(ParamRef)
        new_arg = hargs[arg.param]
        raise "Wrong ParamRef: #{arg.param}" unless new_arg
        new_arg
      else
        @oper.fix_param_ref(hargs)
        arg
      end
    end
  end

  def to_s
    "(#{@oper} #{@args.map(&:to_s).join(' ')})"
  end
end

class ArithOperation < Field

  attr_reader :op

  OPERATIONS = [:add, :sub, :mul, :div, :lt, :le]
  OPER_TO_NAME_MAP = {'+'=>:add, '-'=>:sub, '*'=>:mul, '/'=>:div, '<'=>:lt, '<='=>:le}
  NAME_TO_OPER_MAP = {add: '+', sub: '-', mul: '*', div: '/', lt: '<', le: '<='}

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

  def conditional?
    @op == :lt || @op == :le
  end

  def to_s
    "#{NAME_TO_OPER_MAP[@op]}"
  end
end

########################################################################################################################
# Constraints
#
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
