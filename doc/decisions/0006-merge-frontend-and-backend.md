# 6. Merge Frontend and Backend and switch to Chainlit

Date: 2025-03-22

## Status

Accepted

## Context

The original motivation for separating the _Frontend_ and _Backend_ was to 
facilitate the reusability of the _Backend_ API in scenarios where the 
_Frontend_ might later be replaced by a different technology, such as 
React.JS.

However, maintaining distinct Streamlit-based _Frontend_ and FastAPI-based
_Backend_ services has proven burdensome and has introduced significant 
complexity when implementing features that require real-time audio handling 
or real-time user interfaces. Specifically, the overhead of managing two 
separate containers, synchronizing state, and ensuring authentication 
between them has created operational difficulties.

Streamlit has been helpful for rapidly prototyping user interfaces but has 
shown limitations in extensibility and encountered challenges caused by
its _Async_ implementation. These limitations have resulted in complications 
for certain recent use cases and made real-time audio processing particularly 
problematic.

The original goal of modularity—allowing easy replacement of the user 
interface—can still be achieved by leveraging Chainlit's 
[FastAPI integration](https://docs.chainlit.io/integrations/fastapi). 
This setup ensures that users who wish to adopt a different UI framework
 in the future can simply remove the Chainlit-specific code without 
 significant architectural changes.

## Decision

The following changes will be implemented:
1. Eliminate the _Backend_ container from the source repository and infrastructure configuration.
2. Consolidate the FastAPI logic into the _Frontend_ container.
3. Replace Streamlit with Chainlit, embedding Chainlit within FastAPI under the `/ui` URI path.
4. Configure a default redirect from `/` to `/ui`.
5. Continue to develop HTTP API endpoints in FastAPI, organized under paths other than `/ui`.

## Consequences

This consolidation simplifies the architecture by reducing it to a single service managed in Azure Developer CLI (AZD). The project structure and deployment are streamlined, as there will now be one directory in the kickstarter repository and a single Container App deployed.