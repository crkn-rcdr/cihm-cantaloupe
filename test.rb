# This file is named `test.rb`, in the same folder as `delegates.rb`
# See https://cantaloupe-project.github.io/manual/4.0/delegate-script.html#Testing%20Delegate%20Methods for more
require './delegates'

identifier = ENV.fetch('TEST_IDENTIFIER', '69429/c02f7js0s56k')

obj = CustomDelegate.new
obj.context = {
  'identifier' => identifier,
  'client_ip' => '127.0.0.1',
}

puts JSON.generate(obj.canvas)
puts JSON.generate(obj.s3source_object_info)
puts JSON.generate(obj.httpsource_resource_info)
