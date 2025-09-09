import chainlit as cl
import datetime
from azure.ai.agents.models import Agent
from azure.ai.projects.aio import AIProjectClient
from opentelemetry.trace import get_tracer
from semantic_kernel.agents import (
    AzureAIAgent,
    AzureAIAgentThread,
)
from azure.identity.aio import DefaultAzureCredential
from semantic_kernel.contents import ChatMessageContent

from pattern.debate import DebateOrchestrator
from pattern.foundry_debate import FoundryDebateOrchestrator
from semantic_kernel.connectors.ai.azure_ai_inference import (
    AzureAIInferenceChatCompletion,
)
from semantic_kernel.core_plugins.time_plugin import TimePlugin
from semantic_kernel.kernel import Kernel

from semantic_kernel.agents import (
    AzureAIAgent,
)
from azure.ai.inference.aio import ChatCompletionsClient
import os

from semantic_kernel.contents.text_content import TextContent
from semantic_kernel.contents.function_result_content import FunctionResultContent
from semantic_kernel.contents.function_call_content import FunctionCallContent


class AIFoundryAgentProfile:
    def __init__(self, agent: dict):
        self.agent = agent

    @property
    def name(self) -> str:
        return self.agent["name"]

    @property
    def description(self) -> str:
        return self.agent["description"]

    @property
    def markdown_description(self) -> str:
        return f"**Foundry Agent**: {self.description or 'No description available.'}"

    async def run(
        self, client: AIProjectClient, message: cl.Message, response: cl.Message
    ) -> None:
        agent = AzureAIAgent(client=client, definition=self.agent)
        thread: AzureAIAgentThread = cl.user_session.get("thread", None)

        tracer = get_tracer(__name__)
        with tracer.start_as_current_span(
            agent.id + "-" + datetime.datetime.now().isoformat()
        ):
            agent_response = await agent.get_response(
                messages=message.content, thread=thread
            )
        cl.user_session.set("thread", agent_response.thread)

        response.content = agent_response.content.content
        await response.update()


class DebateProfile:
    def __init__(
        self,
        endpoint: str,
        api_version: str,
        executor_deployment_name: str,
        utility_deployment_name: str,
        credential: DefaultAzureCredential,
    ):
        self.orchestrator = DebateOrchestrator(
            endpoint=endpoint,
            api_version=api_version,
            executor_deployment_name=executor_deployment_name,
            utility_deployment_name=utility_deployment_name,
            credential=credential,
        )

    @property
    def name(self) -> str:
        return "Debate"

    @property
    def description(self) -> str:
        return "A profile for debating topics with multiple perspectives."

    @property
    def markdown_description(self) -> str:
        return (
            "**Debate Profile**: Engage in structured debates on various topics, "
            "encouraging critical thinking and diverse viewpoints."
        )

    async def run(
        self, client: AIProjectClient, message: cl.Message, response: cl.Message
    ) -> None:
        final_step = None
        async for step in self.orchestrator.process_conversation(
            "default_user",  # TODO
            [{"role": "user", "name": "user", "content": message.content}],
        ):
            if step["type"] == "status_update":
                await response.stream_token(f"\n* {step['description']}\n")
            final_step = step

        response.content = final_step["content"]
        await response.update()


class FoundryDebateProfile:
    def __init__(
        self,
        deployment_name: str,
        azure_ai_agents: list[Agent],
        credential: DefaultAzureCredential,
    ):
        self.project_client = AzureAIAgent.create_client(credential=credential)
        self.orchestrator = self.create_orchestrator(
            deployment_name=deployment_name,
            azure_ai_agents=azure_ai_agents,
            credential=credential,
            project_client=self.project_client,
        )
        self.credentials = credential

    @staticmethod
    def create_orchestrator(
        deployment_name: str,
        azure_ai_agents: list[Agent],
        credential: DefaultAzureCredential,
        project_client: AIProjectClient,
    ):
        kernel = Kernel()
        kernel.add_plugin(TimePlugin(), plugin_name="time")

        kernel.add_service(
            AzureAIInferenceChatCompletion(
                service_id="utility",
                ai_model_id=deployment_name,
                client=ChatCompletionsClient(
                    # Using OpenAI endpoint for structured output (see test_ai_inference.py)
                    endpoint=f"{os.environ['AZURE_OPENAI_ENDPOINT']}/deployments/{deployment_name}",
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
                plugins=[TimePlugin()],  # TODO: translate from YAML spec?
            )
            for definition in azure_ai_agents
            if definition.name in ["Writer", "Critic"]
        ]
        return FoundryDebateOrchestrator(
            kernel=kernel,
            agents=agents,
            credential=credential,
            max_rounds=6,
            last_agent_names=[
                "Writer"
            ],  # Only Writer's last response is used for final output
        )

    @property
    def name(self) -> str:
        return "FoundryDebate"

    @property
    def description(self) -> str:
        return "A profile for debating topics with multiple perspectives."

    @property
    def markdown_description(self) -> str:
        return (
            "**Foundry Debate Profile**: Engage in structured debates on various topics, "
            "encouraging critical thinking and diverse viewpoints. Using Foundry Agent Service agents."
        )

    async def run(
        self, client: AIProjectClient, message: cl.Message, response: cl.Message
    ) -> None:
        async def callback(message: ChatMessageContent) -> None:
            def extract_content(message: ChatMessageContent) -> str:
                for item in message.items:
                    match item:
                        case TextContent():
                            return item.text
                        case FunctionCallContent():
                            return f"Tool call: {item.plugin_name}.{item.function_name}({item.arguments})"
                        case FunctionResultContent():
                            return f"Tool result: {item.result}"

            async with cl.Step(name=f"Agent {message.name}", type="llm") as step:
                step.output = extract_content(message)

        # See https://learn.microsoft.com/en-us/semantic-kernel/frameworks/agent/agent-types/azure-ai-agent

        final_message = await self.orchestrator.process_conversation(
            project_client=self.project_client,
            user_id="default_user",  # TODO
            conversation_messages=[
                {"role": "user", "name": "user", "content": message.content}
            ],
            agent_response_callback=callback,
        )

        final_response = cl.Message(
            content=final_message.content,
            author=final_message.name,
        )
        await final_response.send()
