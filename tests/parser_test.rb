# frozen_string_literal: true

require_relative '../parser'
require 'test/unit'

class ParserTest < Test::Unit::TestCase
  # def test_empty_two_variants_type
  #   s = %q(
  #     bool_false$0 = Bool;
  #     bool_true$1 = Bool;
  #   )
  #   tlb = Parser.new.parse(s)
  #   assert_equal(tlb.types.size, 1)
  #   bool_type = tlb.get_type('Bool')
  #   assert_not_nil(bool_type)
  #   assert_equal(bool_type.variants.size, 2)
  #   var_false = bool_type.variants[0]
  #   assert_true(var_false.name == 'bool_false')
  #   assert_equal(var_false.fields.size, 1)
  #   assert_equal(var_false.fields[0].value, 0)
  # end

  # def test_different_length_constructor_and_numbers
  #   s = %q(
  #     one_bit$1 val:(## 3) = Test;
  #     two_bits_a$00 val:uint32 = Test;
  #     two_bits_b$01 val:# = Test;
  #   )
  #   tlb = Parser.new.parse(s)
  #   assert_equal(tlb.types.size, 1)
  #   type = tlb.get_type('Test')
  #   assert_not_nil(type)
  #   assert_equal(type.variants.size, 3)
  #
  #   var0 = type.variants[0]
  #   assert_equal(var0.name, 'one_bit')
  #   assert_equal(var0.fields.size, 2)
  #   assert_true(var0.fields[0].value.is_a? Constant)
  #   assert_equal(var0.fields[0].value.value, 1)
  #   assert_equal(var0.fields[0].value.bits, 1)
  #   assert_true(var0.fields[1].value.is_a? Number)
  #   assert_equal(var0.fields[1].value.bits, 3)
  #
  #   var1 = type.variants[1]
  #   assert_equal(var1.name, 'two_bits_a')
  #   assert_equal(var1.fields.size, 2)
  #   assert_true(var1.fields[0].value.is_a? Constant)
  #   assert_equal(var1.fields[0].value.value, 0)
  #   assert_equal(var1.fields[0].value.bits, 2)
  #   assert_true(var1.fields[1].value.is_a? Number)
  #   assert_equal(var1.fields[1].value.bits, 32)
  #
  #   var2 = type.variants[2]
  #   assert_equal(var2.name, 'two_bits_b')
  #   assert_equal(var2.fields.size, 2)
  #   assert_true(var2.fields[0].value.is_a? Constant)
  #   assert_equal(var2.fields[0].value.value, 1)
  #   assert_equal(var2.fields[0].value.bits, 2)
  #   assert_true(var2.fields[1].value.is_a? Number)
  #   assert_equal(var2.fields[1].value.bits, 32)
  # end
  #
  # def test_empty_constructor_and_unnamed_fields
  #   s = %q(
  #     _ _:(## 3) = Test;
  #   )
  #   tlb = Parser.new.parse(s)
  #   assert_equal(tlb.types.size, 1)
  #   type = tlb.get_type('Test')
  #   assert_not_nil(type)
  #   assert_equal(type.variants.size, 1)
  #   var = type.variants[0]
  #   assert_equal(var.fields.size, 1)
  #   assert_true(var.fields[0].value.is_a?(Number))
  #   assert_equal(var.fields[0].value.bits, 3)
  # end

  # def test_empty_constructor_and_unnamed_fields
  #   s = %q(
  #     _ _:(## 3) = A;
  #     _ _:(## 8) = B;
  #     a$0 val:A = C;
  #     b$1 val:B = C;
  #   )
  #   tlb = Parser.new.parse(s)
  #   assert_equal(tlb.types.size, 3)
  #
  #   type_a = tlb.get_type('A')
  #   assert_not_nil(type_a)
  #
  #   type_b = tlb.get_type('B')
  #   assert_not_nil(type_b)
  #
  #   type_c = tlb.get_type('C')
  #   assert_not_nil(type_c)
  #
  #   assert_equal(type_c.variants.size, 2)
  #
  #   var0 = type_c.variants[0]
  #   assert_equal(var0.fields.size, 2)
  #   assert_true(var0.fields[1].value.is_a?(TypeRef))
  #   assert_equal(var0.fields[1].value.type, type_a)
  #
  #   var1 = type_c.variants[1]
  #   assert_equal(var1.fields.size, 2)
  #   assert_true(var1.fields[1].value.is_a?(TypeRef))
  #   assert_equal(var1.fields[1].value.type, type_b)
  # end

  # def test_field_const_folding
  #   s = %q(
  #     _ value:(int (4 * 8)) = Test;
  #   )
  #   tlb = Parser.new.parse(s)
  #   assert_equal(tlb.types.size, 1)
  #   assert_equal(tlb.get_type('Test').variants.size, 1)
  #   var = tlb.get_type('Test').variants[0]
  #   assert_equal(var.fields.size, 1)
  #   assert_true(var.fields[0].value.is_a?(Number))
  #   assert_equal(var.fields[0].value.bits, 32)
  # end

  def test_var_integer
    s = %q(
      var_int$_ {n:#} len:(#< n) value:(int (len * 8)) = VarInteger n;
    )
    tlb = Parser.new.parse(s)
    assert_equal(tlb.types.size, 1)
    assert_equal(tlb['VarInteger'].variants.size, 1)
    len = tlb['VarInteger']['len']
    value = tlb['VarInteger']['value']
    # assert_true(len.value.is_a?(Number))
    # assert_true(len.bits.is_a?(TypeParam))
    # assert_true(value.value.is_a?(Number))

    tlb.dump()

    varint = tlb['VarInteger'].instantiate(16)
  end

  ##
  # Tlb:
  #   Type[name, cases]
  #     Case[fields, params]


end