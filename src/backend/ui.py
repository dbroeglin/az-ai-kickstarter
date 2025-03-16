import json
import logging
import urllib

import aiohttp
import chainlit as cl

logger = logging.getLogger(__name__)


@cl.set_starters
async def set_starters():
    return [
        cl.Starter(
            label="About cookies",
            message="About cookies",
        ),
        cl.Starter(
            label="About starwars",
            message="About starwars",
        ),
        cl.Starter(
            label="About Mondays",
            message="About Mondays",
        ),
    ]


@cl.on_message
async def main(message: cl.Message):
    topic = message.content.strip()
    msg = cl.Message(content=f"**Generating blog post about {topic}:**\n")

    async with aiohttp.ClientSession() as session:
        try:
            url = urllib.parse.urlparse(message.metadata["location"])
            async with session.post(
                url._replace(path="/blog").geturl(),
                json={"topic": topic, "user_id": message.author},
            ) as response:
                response.raise_for_status()  # Raise an error for bad responses

                async for chunk in response.content.iter_any():
                    chunk_text = chunk.decode("utf-8").strip()
                    if not chunk_text.startswith("{"):
                        await msg.stream_token("\n* " + chunk_text)
                await msg.update()

                blog_data = json.loads(chunk).get("content", "")
                final_element = cl.Text(content=blog_data)
                await cl.Message(
                    content="**Here's the complete blog post**:",
                    elements=[final_element],
                ).send()
        except Exception as e:
            logger.error(f"Error calling API: {e}")
            await cl.Message(content=f"Error generating blog post: {str(e)}").send()
