
class Solution
  attr_accessor :name, :code, :problem, :index, :before, :example, :notes

  def initialize name, code
    @name, @code = name, code
    @before = ''
  end

  def code_block
    result = ''
    
    sol = self
    prob = problem

    prob.around =~ /\b__SOLUTION__\b([^\n]*)/
    args = $1 || ''
    
    sol_meth = "sol_#{sol.index}"
    sol_code = sol.code
    
    unless prob.inline
      result << gsub_indented(<<"END", '__SOLUTION__', sol_code)
def #{sol_meth} #{args}
  __SOLUTION__
end
END
      result << "\n"
      sol_code = "#{sol_meth}"
    end

    result << gsub_indented(prob.around, '__SOLUTION__', sol_code) 
    result << "\n"

    result
  end

  def gsub_indented template, keyword, replacement
    replacement = replacement.dup

    # Determine and remove indentation of first line from replacement.
    replacement =~ /\A(\s*)\S/
    dedent = $1 || ''
    replacement.gsub!(/^#{dedent}/, '')

    # Determine the indentation of the first line containing keyword in the template.
    template =~ /^(\s*)\b#{keyword}\b/
    indent = $1 || ''

    # Indent replacement with the indentation of the keyword.
    replacement.gsub!(/^/, indent)
    # Remove the identation in the replacement, since keyword is already indentend in the template.
    replacement.sub!(/\A#{indent}/, '')

    # Remove last newline.
    replacement.sub!(/\n\Z/, indent)
    
    # Replace keyword with replacement.
    result = template.gsub(/\b#{keyword}\b/, replacement)

    result
  end
end


