# labsprojectfrommetadata.rb
#
# This fact pulls the labs project out of instance metadata

require 'facter'

Facter.add(:labsprojectfrommetadata) do
  setcode do
    domain = Facter::Util::Resolution.exec("hostname -d").chomp
    if (domain.end_with? ".wmflabs") || (domain.end_with? ".labtest")
      # query the nova metadata service at 169.254.169.254
      metadata = Facter::Util::Resolution.exec("curl -f http://169.254.169.254/openstack/2015-10-15/meta_data.json/ 2> /dev/null | jq '.project_id'").chomp
      metadata.slice(1, metadata.length - 2) # strip quotes
    else
      nil
    end
  end
end
