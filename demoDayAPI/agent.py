import logging
import aiohttp
from typing import Annotated
from dotenv import load_dotenv
from livekit.agents import (
    AutoSubscribe,
    JobContext,
    JobProcess,
    WorkerOptions,
    cli,
    llm,
)
from livekit.agents.pipeline import VoicePipelineAgent
from livekit.plugins import openai, deepgram, silero, cartesia, elevenlabs


load_dotenv(dotenv_path=".env.local")
logger = logging.getLogger("voice-agent")


class AssistantFnc(llm.FunctionContext):
    @llm.ai_callable()
    async def get_environment(self):
        """Called when the assistant needs to understand the current environment. Returns a description of what the camera sees."""
        logger.info("getting environment description")
        url = "http://<Replace with your own>/latest"
        async with aiohttp.ClientSession() as session:
            async with session.get(url) as response:
                if response.status == 200:
                    data = await response.json()
                    return f"The environment shows: {data['description']}"
                else:
                    raise Exception(f"Failed to get environment data, status code: {response.status}")


def prewarm(proc: JobProcess):
    proc.userdata["vad"] = silero.VAD.load(activation_threshold=0.8)


chinese_prompt_en = """
假设我们现在处于如下场景：
1. 我是一个儿童
2. 你是一个具有摄像头的陪伴机器人，你能看到我手上拿的物品
3. 场景中存在一些儿童日常能接触到的物品，比如玩具、水果、文具等
请你跟我进行对话，对话的内容需要围绕着我手上拿的物品进行，并且尽可能地用儿童能听懂的简短英语回答我，限制在10个单词以内。
注意，我会用文本的方式告诉你我手上拿的物品是什么，格式为 "[A] 我的问题"，其中 A 代表该物品。
举例说明：
我：[佩奇] 你知道它的名字吗？
你：It's called Peppa.
"""

start_word_en = "你好，我是你的英语学习助手"

chinese_prompt_zh = """
假设我们现在处于如下场景：
1. 我是一个儿童
2. 你是一个具有摄像头的陪伴机器人，你能看到我手上拿的物品
请你跟我进行对话，对话的内容需要围绕着我手上拿的物品进行，并且尽可能地用儿童喜欢的语言回答
注意，我会用文本的方式告诉你我手上拿的物品是什么，格式为 "[A] 我的问题"，其中 A 代表该物品。
另外，不需要在每次回答时先说出这个东西的名字，直接回答我的问题即可。
举例说明：
我：[佩奇] 你知道它的名字吗？
你：它的名字叫佩奇
"""
start_word_zh = "小朋友，我们开始聊天吧"

start_word = start_word_zh
chinese_prompt = chinese_prompt_zh

async def entrypoint(ctx: JobContext):
    initial_ctx = llm.ChatContext().append(
        role="system",
        text=chinese_prompt,
    )

    logger.info(f"connecting to room {ctx.room.name}")
    await ctx.connect(auto_subscribe=AutoSubscribe.AUDIO_ONLY)

    # Wait for the first participant to connect
    participant = await ctx.wait_for_participant()
    logger.info(f"starting voice assistant for participant {participant.identity}")

    # This project is configured to use Deepgram STT, OpenAI LLM and TTS plugins
    # Other great providers exist like Cartesia and ElevenLabs
    # Learn more and pick the best one for your app:
    # https://docs.livekit.io/agents/plugins
    fnc_ctx = AssistantFnc()
    
    assistant = VoicePipelineAgent(
        vad=ctx.proc.userdata["vad"],
        stt=deepgram.STT(language="zh-CN"),
        # stt=elevenlabs.STT(model="eleven_multilingual_v2"),
        llm=openai.LLM.with_azure(
            model="gpt-4o",
            azure_endpoint="<Replace with your own>",
            azure_deployment="gpt-4o", 
            api_key="<Replace with your own>",
            api_version="2024-08-01-preview"
        ),
        tts=elevenlabs.TTS(model="eleven_multilingual_v2"),
        # tts=cartesia.TTS(),
        chat_ctx=initial_ctx,
        # fnc_ctx=fnc_ctx,
    )

    assistant.start(ctx.room, participant)

    # The agent should be polite and greet the user when it joins :)
    await assistant.say(start_word, allow_interruptions=True)


if __name__ == "__main__":
    cli.run_app(
        WorkerOptions(
            entrypoint_fnc=entrypoint,
            prewarm_fnc=prewarm,
        ),
    )
