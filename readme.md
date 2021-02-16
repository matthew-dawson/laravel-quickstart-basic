An interview coding exercise based upon the Laravel quick-start guide
located at https://github.com/laravel/quickstart-basic, which I rather
enjoyed the challenge of.


The ask :
Take a basic PHP website and create a Dockerfile and associated build
scripts so that it can be run within AWS.  When complete, developers
should be able to deploy changes to the codebase via git, without
needing access to the production environment.

The original code is located at https://github.com/laravel/quickstart-basic,
with the original commit of f6cebbc60224bed89e4443dd69a8f770bc75e837 being
the starting point for this execrise.


The requirements :
* Logs should be written somewhere sensible
* Expose metrics from the container (i.e. number of page hits)
* Create a docker-compose file to test the application locally without
external dependencies
* Write a CI script to build the image and run the unit tests within the
/tests/ directory
* Write a CD script to run/update this container in ECS, EKS or even on EC2,
with a public IP address
