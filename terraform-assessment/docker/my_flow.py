# from prefect import flow

# @flow
# def hello_flow():
#     print("Hello from ECS worker!")

# if __name__ == "__main__":
#     hello_flow.deploy(
#         name="hello-deploy",              # Deployment name
#         work_pool_name="ecs-work-pool",   # ECS pool
#         image="prefecthq/prefect:2-latest",  # ECR image
#         tags=["ecs"]
#     )
# from prefect import flow, task
# # from prefect.deployments import Deployment

# @flow(name="yasir-flow")
# def no():
#     print("no")


# @task()
# def yes():
#     print("yes")

# @flow(name="yasir-flow")
# def hello_flow():
#     print("Hello from Prefect Cloud Managed Pool!")
#     print(yes())
#     display = no()
#     print(display)
# hello_flow()



# Create deployment
# if __name__ == "__main__":
#     deployment = Deployment.build_from_flow(
#         flow=hello_flow,
#         name="hello-deploy",     # Deployment name
#         work_pool_name="default" # Your managed pool
#     )
#     deployment.apply()           # Register it in Prefect Cloud








from prefect import flow, task

@flow(name="no-flow")
def no():
    return "no"

@task
def yes():
    return "yes"

@flow(name="yasir-flow")
def hello_flow():
    print("Hello from Prefect Cloud Managed Pool!")

    # run task
    result_yes = yes.submit()
    print("Task result:", result_yes.result())

    # run subflow
    result_no = no()
    print("Subflow result:", result_no)

if __name__ == "__main__":
     hello_flow.deploy(
    name="demo-deployment",
    work_pool_name="ecs-work-pool",
    job_variables={
        "image": "882142483262.dkr.ecr.us-east-1.amazonaws.com/prefect-flow:latest"
    }
)
