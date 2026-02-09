# BEC DATA MANAGEMENT 

I want to plan only the back-end to start, 

When implementing I want each step to be small change (think it like a commit) And I want test to test the newly added functions.

Stop after each new functions I want to be able to see the test working and understand what was written.

## Concept
two essential schemas 
    * Master/main
    * Staging
three roles created using the ROLE features in POSTGRES
    * main admin (super user db admin)
    * admin
    * default (read only in master and write only in staging)

Default to use local db with duck db.
if no current local db , option to load one or initiate one with the master postgres db.

when a user push new lines or modifications it goes in the staging schema.
Before going there is basic validation to see if the new proposed data is within the range of all possibles values.

user need to submit email and name to push (user_name and user_email). 

track changes with triggers and Audit tables

https://exaspark.medium.com/the-ultimate-guide-to-postgresql-data-change-tracking-c3fa88779572

The admin needs to be able to review all changes proposed in the staging schema and handle conflicts if multiple inserts or changes are for the same keys

Once the admin has review and handled conflict (no duplicate lines per keys) he can push sync the master schema with the staging schema.

in production the postgres db will be hosted in digital ocean.

for development and testing I will be using a local postgres hosted in a docker




## Questions
What kind of governence is expected?
what kind of roles are expected? read only , read write + review needed?

