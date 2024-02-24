# frozen_string_literal: true

class IrZero
  def initialize
    @types = {}
  end
end

class Type
  def initialize
    @branches = []
  end
end

class Branch
  def initialize
    @fields = []
    @constraints = []
  end
end