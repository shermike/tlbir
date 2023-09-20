# frozen_string_literal: true

# class String
#   def tohex
#     self.bytes.map{ "%.2x" % _1}.join()
#   end
# end

class BitArray
  attr_reader :reverse_byte, :size, :data
  include Enumerable

  VERSION = "1.3.0"

  def initialize(data: nil, size: 0, reverse_byte: true)
    if data
      if data.is_a?(String)
        @size = data.size * 8
        @reverse_byte = reverse_byte
        if reverse_byte
          @data = data.unpack('B*').pack('b*')
        else
          @data = data.dup
        end
      else
        raise "Unsupported 'data' type: #{data.class}" unless data.is_a?(BitArray)
        @size = data.size
        @reverse_byte = data.reverse_byte
        @data = data.data.dup
      end
    else
      @size = size
      @reverse_byte = reverse_byte
      @data = "\0" * ((size + 7) / 8)
      @data.force_encoding(Encoding::BINARY)
    end
  end

  # Set a bit (1/0)
  def []=(position, value)
    if value != 0 && value != false
      @data.setbyte(position >> 3, @data.getbyte(position >> 3) | (1 << (byte_position(position) % 8)))
    else
      @data.setbyte(position >> 3, @data.getbyte(position >> 3) & ~(1 << (byte_position(position) % 8)))
    end
  end

  # Read a bit (1/0)
  def [](position)
    (@data.getbyte(position >> 3) & (1 << (byte_position(position) % 8))) > 0 ? 1 : 0
  end

  def read_int(pos=0, bits=nil)
    v = @data.unpack('b*')[0]
    bits = @size - pos unless bits
    v[pos, bits].to_i(2)
  end

  def pop
    raise "pop error: bitarray is empty" if @size == 0
    val = self[@size - 1]
    @size -= 1
    val
  end

  # Iterate over each bit
  def each
    return to_enum(:each) unless block_given?
    @size.times { |position| yield self[position] }
  end

  # Returns the data as a string like "0101010100111100," etc.
  def to_s
    if @reverse_byte
      @data.bytes.collect { |ea| ("%08b" % ea).reverse }.join[0, @size]
    else
      @data.bytes.collect { |ea| ("%08b" % ea) }.join[0, @size]
    end
  end

  # Iterates over each byte
  def each_byte
    return to_enum(:each_byte) unless block_given?
    @data.bytes.each{ |byte| yield byte }
  end

  # Returns the total number of bits that are set
  # Use Brian Kernighan's way, see
  # https://graphics.stanford.edu/~seander/bithacks.html#CountBitsSetKernighan
  def total_set
    @data.each_byte.inject(0) { |a, byte| (a += 1; byte &= byte - 1) while byte > 0 ; a }
  end

  def tobytes
    @data.unpack('b*').pack('B*')
  end

  def <<(value)
    @data << "\0" if (@size % 8) == 0
    @size += 1
    self[@size - 1] = value
  end

  private def byte_position(position)
    @reverse_byte ? position : 7 - position
    # @reverse_byte ? 7 - position : position
  end
end


def test_int
  b = BitArray.new
  b << 1  # 0
  b << 0  # 1
  b << 1  # 2
  b << 1  # 3
  b << 0  # 4
  b << 1  # 5
  b << 0  # 6
  b << 0  # 7
  b << 1  # 8
  b << 0  # 9

  raise "Error 1" unless b.read_int(0, 2) == 2
  raise "Error 2" unless b.read_int(3, 6) == 41
  raise "Error 3" unless b.read_int(7, 3) == 2
  raise "Error 4" unless b.read_int(4) == 18
  raise "Error 5" unless b.read_int == 722
end
