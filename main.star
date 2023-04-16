etcd_module = import_module("github.com/laurentluce/kurtosis-etcd-package/main.star")

DEFAULT_NUMBER_OF_NODES = 3
NUM_NODES_ARG_NAME = "num_nodes"
RABBITMQ_NODE_PREFIX="rabbitmq-node-"
RABBITMQ_NODE_IMAGE = "rabbitmq:3.11.13-management"

MANAGEMENT_PORT_ID = "management"
MANAGEMENT_PORT_NUMBER =  15672
MANAGEMENT_PORT_PROTOCOL = "TCP"

AMQP_PORT_ID = "amqp"
AMQP_PORT_NUMBER =  5672
AMQP_PORT_PROTOCOL = "TCP"

FIRST_NODE_INDEX = 0

CONFIG_DIR = "/etc/rabbitmq"
CONFIG_TEMPLATE_PATH =  "github.com/laurentluce/kurtosis-rabbitmq-package/static_files/rabbitmq.conf.tmpl"
CONFIG_TEMPLATE_FILENAME = "rabbitmq.conf"
ENABLED_PLUGINS_TEMPLATE_PATH =  "github.com/laurentluce/kurtosis-rabbitmq-package/static_files/enabled_plugins.tmpl"
ENABLED_PLUGINS_TEMPLATE_FILENAME = "enabled_plugins"

LIB_DIR = "/var/lib/rabbitmq"
ERLANG_COOKIE_PATH =  "github.com/laurentluce/kurtosis-rabbitmq-package/static_files/.erlang.cookie"

def run(plan, args):
    num_nodes = DEFAULT_NUMBER_OF_NODES
    if NUM_NODES_ARG_NAME in args:
        num_nodes = args["num_nodes"]

    if num_nodes == 0:
        fail("Need at least 1 node to start the RabbitMQ cluster got 0")

    etcd_run_output = etcd_module.run(plan, ())

    config_template_and_data = {
        CONFIG_TEMPLATE_FILENAME : struct(
            template = read_file(CONFIG_TEMPLATE_PATH),
            data = {
                "ManagementPort": MANAGEMENT_PORT_NUMBER,
                "AMQPPort": AMQP_PORT_NUMBER,
                "EtcdEndpoint": "{}:{}".format(etcd_run_output["hostname"],  etcd_run_output["port"])
            }
        ),
        ENABLED_PLUGINS_TEMPLATE_FILENAME : struct(
            template = read_file(ENABLED_PLUGINS_TEMPLATE_PATH),
            data = {
            }
        ),
    }
    rendered_config_artifact = plan.render_templates(config_template_and_data, name = "config")

    lib_artifact = plan.upload_files(
        src = ERLANG_COOKIE_PATH,
        name = "lib"
    )

    started_nodes = []
    for node in range(0, num_nodes):
        node_name = get_service_name(node)
        config = get_service_config(node_name, rendered_config_artifact, lib_artifact)
        node = plan.add_service(name = node_name, config = config)
        started_nodes.append(node)

    cluster_status_cmd = "rabbitmqctl cluster_status | grep \"Running Nodes\" -A {} | grep \"rabbit@\" | wc -l | tr -d '\n'".format(num_nodes+1)
    check_cluster = ExecRecipe(
        command = ["/bin/sh", "-c", cluster_status_cmd]
    )

    plan.wait(recipe = check_cluster, field = "output", assertion = "==", target_value = str(num_nodes), timeout = "5m", service_name = get_first_node_name())

    result =  {"node_names": [node.name for node in started_nodes]}

    return result


def get_service_config(node_name, config_artifact, lib_artifact):
    return ServiceConfig(
        image = RABBITMQ_NODE_IMAGE,
        ports = {
            MANAGEMENT_PORT_ID : PortSpec(number = MANAGEMENT_PORT_NUMBER, transport_protocol = MANAGEMENT_PORT_PROTOCOL),
            AMQP_PORT_ID : PortSpec(number = AMQP_PORT_NUMBER, transport_protocol = AMQP_PORT_PROTOCOL),
        },
        env_vars = {
        },
        files = {
            CONFIG_DIR: config_artifact,
            LIB_DIR: lib_artifact,
        }
    )


def get_service_name(node_idx):
    return RABBITMQ_NODE_PREFIX + str(node_idx)


def get_first_node_name():
    return get_service_name(FIRST_NODE_INDEX)
