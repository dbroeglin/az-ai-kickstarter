import pytest
from rich.console import Console
from rich.markdown import Markdown
from rich.panel import Panel
from semantic_kernel.contents.chat_message_content import ChatMessageContent

from pattern.foundry_debate import FoundryDebateOrchestrator
from utils import load_dotenv_from_azd, get_model_deployment
import os
from azure.identity.aio import DefaultAzureCredential
from semantic_kernel.connectors.ai.azure_ai_inference import (
    AzureAIInferenceChatCompletion,
)
from semantic_kernel.core_plugins.time_plugin import TimePlugin
from semantic_kernel.kernel import Kernel

from semantic_kernel.agents import (
    AzureAIAgent,
)
from azure.ai.inference.aio import ChatCompletionsClient
import logging
logging.getLogger("azure.identity").setLevel(logging.INFO)

# Load settings
load_dotenv_from_azd()

console = Console()

@pytest.fixture()
async def orchestrator(mocker):
    mocker.patch(
        "semantic_kernel.core_plugins.time_plugin.TimePlugin.date",
        return_value="Sunday, 12 January, 2031",
    )
    credential = DefaultAzureCredential()
    project_client = AzureAIAgent.create_client(credential=credential)

    deployment_name = get_model_deployment("gpt-4.1-mini").name
    kernel = Kernel()
    kernel.add_plugin(TimePlugin(), plugin_name="time")
    
    kernel.add_service(
        AzureAIInferenceChatCompletion(
            service_id="utility",
            ai_model_id=deployment_name,
            client=ChatCompletionsClient(
                # Using OpenAI endpoint for structured output (see test_ai_inference.py)
                endpoint=f"{os.environ["AZURE_OPENAI_ENDPOINT"]}/deployments/{deployment_name}",
                credential=credential,
                credential_scopes=["https://cognitiveservices.azure.com/.default"],
                api_version=os.environ["AZURE_OPENAI_API_VERSION"],
            ),
        )
    )
    agents = [
        # Wrapping AI Foundry Agents in Semantic Kernel's AzureAIAgent
        AzureAIAgent(
                    client=project_client,
                    definition=definition,
                    plugins=[TimePlugin()], # TODO: translate from YAML spec?
        )
        async for definition in project_client.agents.list_agents()
        if definition.name in ["Writer", "Critic"]
    ]
    return FoundryDebateOrchestrator(
        kernel=kernel,
        agents=agents,
        credential=credential,
        max_rounds=6,
        last_agent_names=["Writer"],  # Only Writer's last response is used for final output
    )


async def test_blog_generation(orchestrator):
    console.print() # start an a blank line
    conversation_messages = [
        {
            "role": "user",
            "content": "A blog about cookies",
        }
    ]

    async def agent_response_callback(message: ChatMessageContent) -> None:
        """Callback function to retrieve agent responses."""
        console.print(message)
        console.print(Panel(Markdown(message.content), title=f"Agent: {message.name} ({message.role.name})"))

    async with AzureAIAgent.create_client(
        credential=DefaultAzureCredential()
    ) as project_client:
        final_message = await orchestrator.process_conversation(
            project_client,
            "test_user",
            conversation_messages,
            agent_response_callback=agent_response_callback,
        )

    assert final_message is not None
    assert "01/12/2031" in final_message.content
    assert "cookies" in final_message.content.lower()

    console.rule()
    console.print(Panel(Markdown(final_message.content), title="Final Response"))
