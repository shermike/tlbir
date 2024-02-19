require_relative '../bitarray'
require 'digest'
require 'digest/crc32'
require 'zlib'

def hex(a)
  a.bytes.map{ "%.2x" % _1}.join()
end

class CellData
  attr_accessor :bits

  def initialize(max_length = 1023)
    @bits = BitArray.new
    @max_length = max_length
  end

  def put_bool(element)
    if !@max_length.nil? && @bits.size >= @max_length
      raise 'Cell overflow'
    end

    @bits << element
  end

  def put_uint(uint, bitsize)
    if bitsize <= 0 || (2**bitsize - 1 < uint)
      raise "Not enough bits (#{bitsize}) to encode integer (#{uint})"
    end

    bitsize.downto(1) do |i|
      k = 2**(i - 1)
      if uint / k == 1
        put_bool(1)
        uint -= k
      else
        put_bool(0)
      end
    end
  end

  def put_uint8(uint)
    put_uint(uint, 8)
  end

  def put_bytes(_bytes)
    _bytes.each_byte { |byte| put_uint8(byte) }
  end

  def put_int(_int, bitsize)
    if bitsize == 1
      if [0, -1].include?(_int)
        put_bool(_int == -1)
      else
        raise "Not enough bits (#{bitsize}) to encode integer (#{_int})"
      end
    end

    if _int < 0
      put_bool(1)
      s = 2**(bitsize - 1)
      put_uint(s - _int, bitsize - 1)
    else
      put_bool(0)
      put_uint(_int, bitsize - 1)
    end
  end

  def concatenate(another_cell_data)
    if length + another_cell_data.length > 1023
      raise "Not enough bits to concatenate cells: #{length} + #{another_cell_data.length}"
    end

    @bits.concat(another_cell_data.bits)
  end

  def top_up
    l = length
    additional_bits = (l / 8.0).ceil - l / 8
    additional_bits -= 1 if (l / 8.0).ceil == 128

    additional_bits.times do |i|
      put_bool(i == 0 ? 1 : 0)
    end
  end

  def copy
    cd = CellData.new
    cd.bits = BitArray.new(data: @bits)
    cd
  end

  def length
    @bits.size
  end

  def top_upped_bytes
    t = copy
    t.top_up
    t.bits.tobytes
  end

  def from_bytes(data, top_upped = false)
    @bits = BitArray.new(data: data)
    return unless top_upped

    x = @bits.pop
    while x == 0
      x = @bits.pop
    end
  end

  def ==(another_cell_data)
    @bits.to_s == another_cell_data.bits.to_s && length == another_cell_data.length
  end

  def to_s
    if length % 8 != 0
      x = copy
      x.top_up
      "#{x.bits.to_s}_"
    else
      @bits.to_s
    end
  end
end

class Builder
  def initialize
    @root = Cell.new
    @current = @root
  end

  def build(&block)
    self.instance_eval(&block)
    @root
  end

  def ref(&block)
    old_cell = @current
    cell = Cell.new
    @current.refs << @current = cell
    self.instance_eval(&block)
    @current = old_cell
  end

  def method_missing(method, *args)
    case
    when method.start_with?('uint')
      raise "One argument required" if args.empty?
      bits = method[4..-1].to_i
      raise "Invalid bits" if bits == 0
      @current.data.put_uint(args[0], bits)
    else
      raise "Unknown build method: #{method}"
    end
  end
end

class Cell
  attr_reader :data, :refs
  attr_accessor :special

  def initialize
    @data = CellData.new
    @refs = []
    @special = false
  end

  def self.build(&block)
    Builder.new.build(&block)
  end

  def level
    raise NotImplementedError, 'Calculating level not implemented for special cells' if special

    max_level = 0
    refs.each do |k|
      max_level = k.level if k.level > max_level
    end
    max_level
  end

  def pop_cell
    res = @refs.first
    @refs = @refs[1..-1]
    res
  end

  def special?
    special
  end

  def explicitly_stored_hashes?
    false
  end

  def depth
    max_depth = 0
    unless refs.empty?
      refs.each do |k|
        max_depth = k.depth if k.depth > max_depth
      end
      max_depth += 1
    end
    max_depth
  end

  def encoded_depth
    (depth / 256).chr + (depth % 256).chr
  end

  def concatenate(another_cell)
    data.concatenate(another_cell.data)
    @refs += another_cell.refs
  end

  def refs_descriptor
    (refs.length + (special? ? 8 : 0) + level * 32).chr
  end

  def bits_descriptor
    ((data.length / 8) + (data.length.to_f / 8).ceil).chr
  end

  def data_with_descriptors
    refs_descriptor + bits_descriptor + data.top_upped_bytes
  end

  def repr
    ret = data_with_descriptors
    @refs.each { ret << _1.encoded_depth() }
    @refs.each { ret << _1.hash() }
    ret
  end

  def hash
    hasher = Digest::SHA256.new
    hasher.update(repr())
    hasher.digest
  end

  def serialize_for_boc(cells_index, ref_size)
    ret = data_with_descriptors
    raise NotImplementedError, 'Do not support explicitly stored hashes yet' if explicitly_stored_hashes?

    refs.each do |k|
      ref_hash = k.hash
      ref_index_int = cells_index[ref_hash]
      ref_index_hex = format('%x', ref_index_int)
      ref_index_hex = "0#{ref_index_hex}" if ref_index_hex.length.odd?
      reference = [ref_index_hex].pack('H*')
      ret += reference
    end
    ret
  end

  def serialize_for_boc_size(cells_index, ref_size)
    serialize_for_boc(cells_index, ref_size).length
  end

  def build_indexes
    def move_to_end(index_hashmap, topological_order_array, target)
      target_index = index_hashmap[target]
      index_hashmap.each do |hash, index|
        if index > target_index
          index_hashmap[hash] -= 1
        end
      end
      index_hashmap[target] = topological_order_array.length - 1
      data = topological_order_array[target_index]
      topological_order_array << data
      data[1].refs.each do |subcell|
        index_hashmap, topological_order_array = move_to_end(index_hashmap, topological_order_array, subcell.hash)
      end
      [index_hashmap, topological_order_array]
    end

    def tree_walk(cell, topological_order_array, index_hashmap, parent_hash = nil)
      cell_hash = cell.hash
      if index_hashmap.key?(cell_hash)
        if parent_hash
          if index_hashmap[parent_hash] > index_hashmap[cell_hash]
            index_hashmap, topological_order_array = move_to_end(index_hashmap, topological_order_array, cell_hash)
          end
        end
        return [topological_order_array, index_hashmap]
      end
      index_hashmap[cell_hash] = topological_order_array.length
      topological_order_array << [cell_hash, cell]
      cell.refs.each do |subcell|
        topological_order_array, index_hashmap = tree_walk(subcell, topological_order_array, index_hashmap, cell_hash)
      end
      [topological_order_array, index_hashmap]
    end

    tree_walk(self, [], {})
  end

  def serialize_boc(has_idx = true, hash_crc32 = true, has_cache_bits = false, flags = 0)
    topological_order, index_hashmap = build_indexes
    cells_num = topological_order.length
    s = cells_num.bit_length
    s_bytes = [s].pack('C').length
    full_size = 0
    cell_sizes = {}
    topological_order.each do |(_hash, subcell)|
      cell_sizes[_hash] = subcell.serialize_for_boc_size(index_hashmap, s_bytes)
      full_size += cell_sizes[_hash]
    end

    offset_bits = full_size.bit_length
    offset_bytes = [offset_bits].pack('C').length
    serialization = CellData.new(nil)
    serialization.put_bytes(reach_boc_magic_prefix)
    serialization.put_uint(has_idx ? 1 : 0, 1)
    serialization.put_uint(hash_crc32 ? 1 : 0, 1)
    serialization.put_uint(has_cache_bits ? 1 : 0, 1)
    serialization.put_uint(flags, 2)
    serialization.put_uint(s_bytes, 3)
    serialization.put_uint8(offset_bytes)
    serialization.put_uint(cells_num, s_bytes * 8)
    serialization.put_uint(1, s_bytes * 8) # One root for now
    serialization.put_uint(0, s_bytes * 8) # Complete BOCs only
    serialization.put_uint(full_size, offset_bytes * 8)
    serialization.put_uint(0, s_bytes * 8) # Root should have index 0
    if has_idx
      topological_order.each do |(_hash, subcell)|
        serialization.put_uint(cell_sizes[_hash], offset_bytes * 8)
      end
    end
    topological_order.each do |(_hash, subcell)|
      refcell_ser = subcell.serialize_for_boc(index_hashmap, offset_bytes)
      refcell_ser.each_byte do |byte|
        serialization.put_uint8(byte)
      end
    end
    ser_arr = serialization.top_upped_bytes
    ser_arr += [Digest::CRC32c.checksum(ser_arr)].pack('V') if hash_crc32
    ser_arr
  end

  def self.deserialize_boc(boc)
    bocs_prefixes = [reach_boc_magic_prefix, lean_boc_magic_prefix, lean_boc_magic_prefix_crc]
    prefix = boc[0, 4]
    boc = boc[4..-1]
    raise 'Unknown boc prefix' unless bocs_prefixes.include?(prefix)
    if prefix == reach_boc_magic_prefix
      (has_idx, hash_crc32, has_cache_bits, flags, size_bytes, boc) = parse_flags(boc)
      root_list = true
    elsif prefix == lean_boc_magic_prefix
      (has_idx, hash_crc32, has_cache_bits, flags, size_bytes) = [1, 0, 0, 0, boc[0].ord]
      boc = boc[1..-1]
      root_list = false
    elsif prefix == lean_boc_magic_prefix_crc
      (has_idx, hash_crc32, has_cache_bits, flags, size_bytes) = [1, 1, 0, 0, boc[0].ord]
      boc = boc[1..-1]
      root_list = false
    end
    offset_bytes = boc[0].ord
    boc = boc[1..-1]
    cells_num = int_from_bytes(boc[0, size_bytes])
    boc = boc[size_bytes..-1]
    roots_num = int_from_bytes(boc[0, size_bytes])
    boc = boc[size_bytes..-1]
    absent_num = int_from_bytes(boc[0, size_bytes])
    boc = boc[size_bytes..-1]
    raise 'Absent cells found, not supported yet' unless absent_num == 0
    tot_cells_size = int_from_bytes(boc[0, offset_bytes])
    boc = boc[offset_bytes..-1]
    if root_list
      raise 'Only 1 root supported for now' if roots_num > 1
      roots_indexes = []
      (0...roots_num).each do
        ri = int_from_bytes(boc[0, size_bytes])
        boc = boc[size_bytes..-1]
        roots_indexes << ri
      end
    else
      roots_indexes = [0]
    end
    offsets = []
    if has_idx
      (0...cells_num).each do
        o = int_from_bytes(boc[0, offset_bytes])
        boc = boc[offset_bytes..-1]
        offsets << o
      end
    end
    cells = []
    (0...cells_num).each do
      (unfinished_cell, ser) = deserialize_cell_data(boc, size_bytes)
      cells << unfinished_cell
      boc = ser
    end
    cells = substitute_indexes_with_cells(cells)
    # raise 'CRC32 check failed' if hash_crc32 && Digest::CRC32c.checksum(boc[0..-5]) != boc[-4..-1].unpack('V')[0]
    cells[0]
  end

  def copy
    ret = Cell.new
    ret.data = @data.copy
    ret.refs = @refs.dup
    ret.special = @special
    ret
  end

  def serialize_to_object
    ret = { 'data' => { 'b64' => '', 'len' => 0 }, 'refs' => [], 'special' => false }
    @refs.each do |r|
      ret['refs'] << r.serialize_to_object
    end
    ret['data']['b64'] = [@data.data.pack('C*')].pack('m0')
    ret['data']['len'] = @data.length
    ret['special'] = @special
    ret
  end

  def serialize_to_json
    serialize_to_object.to_json
  end

  def ==(another_cell)
    return false unless @refs.length == another_cell.refs.length

    @refs.each_with_index do |ref, i|
      return false unless ref == another_cell.refs[i]
    end
    @data == another_cell.data
  end
end

def test_boc_serialization
  c0 = Cell.new
  res = c0.serialize_boc(false)
  reference_serialization_0 = [0xB5, 0xEE, 0x9C, 0x72, 0x41, 0x01, 0x01, 0x01, 0x00, 0x02, 0x00, 0x00, 0x00, 0x4C, 0xAC, 0xB9, 0xCD].pack('C*')
  raise 'Wrong empty cell boc-serialization' unless res == reference_serialization_0

  c1 = Cell.new
  c1.data.put_uint8(0)
  res = c1.serialize_boc(false)
  reference_serialization_1 = [0xB5, 0xEE, 0x9C, 0x72, 0x41, 0x01, 0x01, 0x01, 0x00, 0x03, 0x00, 0x00, 0x02, 0x00, 0xD3, 0x67, 0xDC, 0x41].pack('C*')
  raise 'Wrong <b 0 8 u, b> cell boc-serialization' unless res == reference_serialization_1

  c1 = Cell.new
  c2 = Cell.new
  c1.data.put_uint8(0)
  c2.data.put_uint8(73)
  c1.refs << c2
  res = c1.serialize_boc(false)
  reference_serialization_2 = [0xB5, 0xEE, 0x9C, 0x72, 0x41, 0x01, 0x02, 0x01, 0x00, 0x07, 0x00, 0x01, 0x02, 0x00, 0x01, 0x00, 0x02, 0x49, 0x95, 0xC5, 0xFE, 0x15].pack('C*')
  raise "'<b 0 8 u, <b 73 8 u, b> ref, b>' cell boc-serialization" unless res == reference_serialization_2
end

def parse_flags(serialization)
  header_byte = serialization[0].ord
  serialization = serialization[1..-1]
  has_idx = (header_byte & 128) > 0
  hash_crc32 = (header_byte & 64) > 0
  has_cache_bits = (header_byte & 32) > 0
  header_byte %= 32
  flags = header_byte >> 3
  size_bytes = header_byte % 8
  [has_idx, hash_crc32, has_cache_bits, flags, size_bytes, serialization]
end

def deserialize_cell_data(ser, index_size)
  d1, d2, ser = ser[0].ord, ser[1].ord, ser[2..-1]
  level = d1 / 32
  d1 %= 32
  h = d1 / 16
  d1 %= 16
  raise 'Cell with explicit hash references are not supported yet' if h > 0
  s, r = d1 / 8, d1 % 8
  raise 'Cell with explicit hash references are not supported yet (r>4)' if r > 4
  not_full = (d2 % 2) == 1
  data_size = not_full ? (d2 + 1) / 2 : d2 / 2
  cell_data = ser[0, data_size]
  ser = ser[data_size..-1]
  c = Cell.new
  c.special = s > 0
  c.data.from_bytes(cell_data, top_upped: not_full)
  r.times do
    # ref_index = ser[0, index_size].unpack('C*').pack('C*').to_i
    ref_index = int_from_bytes(ser[0, index_size])
    ser = ser[index_size..-1]
    c.refs << ref_index
  end
  [c, ser]
end

def substitute_indexes_with_cells(cells)
  (cells.length - 1).downto(0).each do |i|
    (0...cells[i].refs.length).each do |j|
      cells[i].refs[j] = cells[cells[i].refs[j]]
    end
  end
  cells
end

def int_from_bytes(str)
  str.bytes.reduce(0) { |acc, byte| (acc << 8) | byte }
end

def deserialize_cell_from_object(data)
  cell = Cell.new
  cell.data.from_bytes(Base64.decode64(data['data']['b64']))
  cell.data.bits = cell.data.bits[0, data['data']['len']]
  data['refs'].each do |r|
    cell.refs << deserialize_cell_from_object(r)
  end
  cell.special = data['special']
  cell
end

def deserialize_cell_from_json(json_data)
  deserialize_cell_from_object(JSON.parse(json_data))
end

def test_boc_deserialization
  c1 = Cell.new
  c2 = Cell.new
  c3 = Cell.new
  c4 = Cell.new
  c1.data.put_uint(2 ** 25, 26)
  c2.data.put_uint(2 ** 37, 38)
  c3.data.put_uint(2 ** 41, 42)
  c4.data.put_uint(2 ** 44 - 2, 44)
  c2.refs << c3
  c1.refs << c2
  c1.refs << c4
  serialized_c1 = c1.serialize_boc(false)

  dc1 = deserialize_boc(serialized_c1)
  raise 'Wrong data' unless dc1.data == c1.data
  raise 'Wrong ref data' unless dc1.refs[0].data == c2.data
  raise 'Wrong ref data' unless dc1.refs[1].data == c4.data
  raise 'Wrong ref ref data' unless dc1.refs[0].refs[0].data == c3.data
end

class Slice < Cell
  def initialize(cell)
    @data = cell.data.copy
    @refs = cell.refs.dup
    raise 'Cell is special, slicing not supported' if cell.special
    @special = cell.special
  end
end

def reach_boc_magic_prefix; "\xB5\xEE\x9C\x72".force_encoding(Encoding::BINARY); end
def lean_boc_magic_prefix; "\x68\xff\x65\xf3".force_encoding(Encoding::BINARY); end
def lean_boc_magic_prefix_crc; "\xac\xc3\xa7\x28".force_encoding(Encoding::BINARY); end

# if true
#   test_boc_serialization
#   test_boc_deserialization
# else
#   c = CellData.new
#   c.put_bool(true)
#   c.put_bool(false)
#   puts c.data.pop
#   puts c.data.pop
# end