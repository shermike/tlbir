# frozen_string_literal: true

require_relative '../parser'
require_relative '../decoder'
require_relative '../boc/cell'
require 'test/unit'


class ParserTest < Test::Unit::TestCase

  def test_empty_two_variants_type
    s = %q(
      bool_false$0 = Bool;
      bool_true$1 = Bool;
    )
    tlb = Parser.new.parse(s)
    assert_equal(tlb.types.size, 1)
    bool_type = tlb.get_type('Bool')
    assert_not_nil(bool_type)
    assert_equal(bool_type.variants.size, 2)
    var_false = bool_type.variants[0]
    assert_true(var_false.name == 'bool_false')
    assert_equal(var_false.fields.size, 1)
    assert_equal(var_false.fields[0].value, 0)
  end

  def test_different_length_constructor_and_numbers
    s = %q(
      one_bit$1 val:(## 3) = Test;
      two_bits_a$00 val:uint32 = Test;
      two_bits_b$01 val:# = Test;
    )
    tlb = Parser.new.parse(s)
    assert_equal(tlb.types.size, 1)
    type = tlb.get_type('Test')
    assert_not_nil(type)
    assert_equal(type.variants.size, 3)

    var0 = type.variants[0]
    assert_equal(var0.name, 'one_bit')
    assert_equal(var0.fields.size, 2)
    assert_equal(var0.fields[0].class, Constant)
    assert_equal(var0.fields[0].value, 1)
    assert_equal(var0.fields[0].bits, 1)
    assert_true(var0.fields[1].is_a? Number)
    assert_equal(var0.fields[1].bits, 3)

    var1 = type.variants[1]
    assert_equal(var1.name, 'two_bits_a')
    assert_equal(var1.fields.size, 2)
    assert_true(var1.fields[0].is_a? Constant)
    assert_equal(var1.fields[0].value, 0)
    assert_equal(var1.fields[0].bits, 2)
    assert_true(var1.fields[1].is_a? Number)
    assert_equal(var1.fields[1].bits, 32)

    var2 = type.variants[2]
    assert_equal(var2.name, 'two_bits_b')
    assert_equal(var2.fields.size, 2)
    assert_true(var2.fields[0].is_a? Constant)
    assert_equal(var2.fields[0].value, 1)
    assert_equal(var2.fields[0].bits, 2)
    assert_true(var2.fields[1].is_a? Number)
    assert_equal(var2.fields[1].bits, 32)
  end

  def test_empty_constructor_and_unnamed_fields
    s = %q(
      _ _:(## 3) = A;
      _ _:(## 8) = B;
      a$0 val:A = C;
      b$1 val:B = C;
    )
    tlb = Parser.new.parse(s)
    assert_equal(tlb.types.size, 3)

    type_a = tlb['A']
    assert_not_nil(type_a)

    type_b = tlb['B']
    assert_not_nil(type_b)

    type_c = tlb['C']
    assert_not_nil(type_c)

    assert_equal(type_c.variants.size, 2)

    var0 = type_c.variants[0]
    assert_equal(var0.fields.size, 2)
    assert_true(var0.fields[1].is_a?(TypeRef))
    assert_equal(var0.fields[1].type, type_a)

    var1 = type_c.variants[1]
    assert_equal(var1.fields.size, 2)
    assert_true(var1.fields[1].is_a?(TypeRef))
    assert_equal(var1.fields[1].type, type_b)
  end

  def test_field_const_folding
    s = %q(
      _ value:(int (4 * 8)) = Test;
    )
    tlb = Parser.new.parse(s)
    assert_equal(tlb.types.size, 1)
    assert_equal(tlb.get_type('Test').variants.size, 1)
    var = tlb.get_type('Test').variants[0]
    assert_equal(var.fields.size, 1)
    assert_true(var.fields[0].is_a?(Number))
    assert_equal(var.fields[0].bits, 32)
  end

  def test_var_integer
    s = %q(
      var_int$_ {n:#} len:(#< n) value:(int (len * 8)) = VarInteger n;
    )
    tlb = Parser.new.parse(s)
    assert_equal(tlb.types.size, 1)
    assert_equal(tlb['VarInteger'].variants.size, 1)
    len = tlb['VarInteger'][0]['len']
    value = tlb['VarInteger'][0]['value']
    assert_equal(len.class, Number)
    assert_equal(len.bits.class, Expression)
    assert_equal(value.class, Number)

    tlb2 = Tlb.new
    tlb2.add_type('VarInteger', tlb['VarInteger'].instantiate([16]))
    assert_true(tlb2['VarInteger'][0]['len'].bits.is_a?(Constant))
    assert_equal(tlb2['VarInteger'][0]['len'].bits.value, 4)
  end

  def test_cell_ref_1
    s = %q(
      a$01 c:(## 9) = X;
      b$11 d:(## 12) = X;
      _ x:^X = Ref1;
    )
    tlb = Parser.new.parse(s)
    ref1 = tlb['Ref1']
    assert_equal(ref1.variants[0].fields.count, 1)
    assert_equal(ref1[0]['x'].class, TypeRef)
    assert_true(ref1[0]['x'].cell_ref)
  end

  def test_cell_ref_2
    s = %q(
      _ {n:#} a:(## n) = T n;
      _ x:^(T 12) = Ref2;
    )
    tlb = Parser.new.parse(s)
    tlb.dump

    ref2 = tlb['Ref2']
    assert_equal(ref2.variants[0].fields.count, 1)
    assert_true(ref2[0]['x'].type_ref?)
    assert_true(ref2[0]['x'].oper.cell_ref)
  end

  def test_type_ref
    s = %q(
      a$01 c:(## 9) e:(## 23) = X;
      b$11 d:(## 12) f:(## 13) = X;
      _ v:# x:X = Test;
    )
    tlb = Parser.new.parse(s)
    var = tlb['Test'].variants[0]
    assert_equal(var.fields.count, 2)
    assert_equal(var.fields[0].class, Number)
    assert_equal(var.fields[1].class, TypeRef)

    # Decoding 'a'
    boc = Cell.build {
      uint32 0x87654321
      uint2  0b01
      uint9  0x123
      uint23  0xaaaaa
    }.serialize_boc

    decoder = Decoder.new(tlb, Cell.deserialize_boc(boc))
    data = decoder.decode(tlb['Test'])
    assert_equal(data, {v: 0x87654321, x: {cons: 'a', c: 0x123, e:0xaaaaa}})

    # Decoding 'b'
    boc = Cell.build {
      uint32 0x123
      uint2  0b11
      uint12  0xafd
      uint13  0xbcd
    }.serialize_boc

    decoder = Decoder.new(tlb, Cell.deserialize_boc(boc))
    data = decoder.decode(tlb['Test'])
    assert_equal(data, {v: 0x123, x: {cons: 'b', d: 0xafd, f:0xbcd}})

    # Decoding invalid
    boc = Cell.build {
      uint32 0x123
      uint2  0b10
      uint12  0xafd
      uint13  0xbcd
    }.serialize_boc

    decoder = Decoder.new(tlb, Cell.deserialize_boc(boc))
    assert_raise(RuntimeError.new('No variants found')) { decoder.decode(tlb['Test']) }
  end

  def test_type_ref_with_params
    s = %q(
      a$01 c:(## n) = X n;
      b$11 d:(## n) = X n;
      _ x:(X 3) = Test;
    )
    tlb = Parser.new.parse(s)
    var = tlb['Test'].variants[0]
    assert_equal(var.fields.count, 1)
    assert_true(var['x'].type_ref?)
    assert_equal(var['x'].oper.type['a']['c'].bits.class, ParamRef)
    assert_equal(var['x'].oper.type['b']['d'].bits.class, ParamRef)
  end

end