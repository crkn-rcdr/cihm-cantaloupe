import os
import swiftclient  
import sys
from keystoneauth1 import session
from keystoneauth1.identity import v3

###
# environment
SWIFT_AUTH_URL = os.getenv("SWIFT_AUTH_URL")
SWIFT_USERNAME = os.getenv("SWIFT_USERNAME")
SWIFT_PASSWORD = os.getenv("SWIFT_PASSWORD")
SWIFT_TENNANT = os.getenv("SWIFT_TENNANT")

###
# Enter password in auth plugin
auth = v3.Password(auth_url=SWIFT_AUTH_URL,
                   username=SWIFT_USERNAME,
                   password=SWIFT_PASSWORD,
                   user_domain_name=SWIFT_TENNANT,
                   project_name=SWIFT_TENNANT,
                   project_domain_name=SWIFT_TENNANT)

# Create session
keystone_session = session.Session(auth=auth)

# create Swift connection
conn = swiftclient.Connection(session=keystone_session)

# Define the container name and prefix you want to list
# sys.argv contains the command line arguments
container_name = sys.argv[1]
base_filename = sys.argv[2]

# TODO - the container list with prefix command doesn't work with any of our accounts 
# in the access-files container specifically. 
# When we move to a new openstack swift, we'll be able to use that method instead
# which should be faster.

# List of file extensions to check
file_extensions = [".jpg", ".tiff", ".jp2"] # jpg first because all new images from IIIF Presentation API flow will be jpg

# Iterate over each file extension and check if the file exists in the container
for ext in file_extensions:
    object_name = base_filename + ext
    try:
        # Attempt to retrieve the object from Swift
        response = conn.get_object(container_name, object_name)
        print(object_name)
        break
    except Exception as e:
        continue