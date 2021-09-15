# This file is named `test.rb`, in the same folder as `delegates.rb`
# See https://cantaloupe-project.github.io/manual/4.0/delegate-script.html#Testing%20Delegate%20Methods for more
require './delegates'

obj = CustomDelegate.new
obj.context = {
  'identifier' => '69429/c0nz80n18k93',
  'client_ip' => '127.0.0.1',
}

puts JSON.generate(obj.canvas)
