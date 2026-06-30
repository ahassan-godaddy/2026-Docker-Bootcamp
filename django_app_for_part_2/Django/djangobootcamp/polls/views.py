from django.shortcuts import get_object_or_404, render
from django.http import HttpResponseRedirect, HttpResponse
from django.urls import reverse
from django.utils import timezone
from django.views import generic

from .models import Choice, Question
import hashlib
import os
import time

import redis
import requests

# Where to find the local LLM. Defaults to Docker Model Runner's
# OpenAI-compatible endpoint, which is reachable from any container as
# `model-runner.docker.internal` when DMR is enabled in Docker Desktop.
# Both values can be overridden from docker-compose.yml.
LLM_BASE_URL = os.environ.get(
    "LLM_BASE_URL", "http://model-runner.docker.internal/engines/v1"
)
LLM_MODEL = os.environ.get("LLM_MODEL", "ai/smollm2")

# Valkey cache (the same image we used in Part 1). We use it to cache LLM
# answers so that asking the same question twice is instant the second time.
# `redis` is the client library; Valkey speaks the same protocol.
CACHE_HOST = os.environ.get("CACHE_HOST", "cache")
CACHE_PORT = int(os.environ.get("CACHE_PORT", "6379"))
CACHE_TTL = int(os.environ.get("CACHE_TTL", "3600"))  # seconds


def _cache_client():
    """Return a Valkey client, or None if caching is turned off.

    We never want a cache outage to take down the endpoint, so callers treat
    a None client (or any error) as a simple cache miss.
    """
    if not CACHE_HOST:
        return None
    return redis.Redis(
        host=CACHE_HOST,
        port=CACHE_PORT,
        db=0,
        decode_responses=True,
        socket_connect_timeout=1,
        socket_timeout=1,
    )


class IndexView(generic.ListView):
    template_name = 'polls/index.html'
    context_object_name = 'latest_question_list'

    def get_queryset(self):
        """
        Return the last five published questions (not including those set to be
        published in the future).
        """
        return Question.objects.filter(
            pub_date__lte=timezone.now()
        ).order_by('-pub_date')[:5]


class DetailView(generic.DetailView):
    model = Question
    template_name = 'polls/detail.html'

    def get_queryset(self):
        """
        Excludes any questions that aren't published yet.
        """
        return Question.objects.filter(pub_date__lte=timezone.now())


def vote(request, question_id):
    question = get_object_or_404(Question, pk=question_id)
    try:
        selected_choice = question.choice_set.get(pk=request.POST['choice'])
    except (KeyError, Choice.DoesNotExist):
        # Redisplay the question voting form.
        return render(request, 'polls/detail.html', {
            'question': question,
            'error_message': "You didn't select a choice.",
        })
    else:
        selected_choice.votes += 1
        selected_choice.save()
        # Always return an HttpResponseRedirect after successfully dealing
        # with POST data. This prevents data from being posted twice if a
        # user hits the Back button.
        return HttpResponseRedirect(reverse('polls:results',
                                            args=(question.id,)))


def i_take_so_long_to_load(request, how_long=5):
    all_questions = Question.objects.all()
    all_answers = Choice.objects.all()
    time.sleep(int(how_long))
    return HttpResponse('I took so long to load! I slept for ' + str(how_long) + ' seconds! I have ' + str(
        len(all_questions)) + ' questions and ' + str(len(all_answers)) + ' answers.')


def raise_error(request):
    raise Exception('This is a test error')


def ask(request):
    """Proxy a question to a local LLM, with a Valkey cache in front of it.

    This is the whole point: our Django container makes an HTTP call to a
    model that's running on the same machine, with no cloud and no API keys.
    We put a Valkey cache in front of it so that asking the same question
    twice is instant the second time (the "cache-aside" pattern).

    Because both `requests` and the `redis` client are auto-instrumented by
    OpenTelemetry, the LLM call and the cache lookups each show up as their
    own spans in the APM waterfall. A cache miss looks slow (Valkey lookup +
    LLM call); a cache hit looks fast (just the Valkey lookup).
    """
    context = {"model": LLM_MODEL}

    if request.method == "POST":
        question = (request.POST.get("question") or "").strip()
        context["question"] = question

        if not question:
            context["error"] = "Please type a question first."
            return render(request, "polls/ask.html", context)

        started = time.monotonic()

        # Build a cache key from the model + question so different models or
        # questions never collide.
        cache = _cache_client()
        cache_key = "ask:" + hashlib.sha256(
            f"{LLM_MODEL}:{question}".encode("utf-8")
        ).hexdigest()

        # Step 1 of cache-aside: look in the cache first.
        cached_answer = None
        if cache is not None:
            try:
                cached_answer = cache.get(cache_key)
            except redis.RedisError:
                cached_answer = None  # a cache outage is just a miss

        if cached_answer is not None:
            context["answer"] = cached_answer
            context["cached"] = True
            context["elapsed"] = round(time.monotonic() - started, 2)
            return render(request, "polls/ask.html", context)

        # Step 2 of cache-aside: on a miss, ask the model...
        try:
            response = requests.post(
                f"{LLM_BASE_URL}/chat/completions",
                json={
                    "model": LLM_MODEL,
                    "messages": [
                        {
                            "role": "system",
                            "content": "You are a helpful assistant. Answer in 2-3 short sentences.",
                        },
                        {"role": "user", "content": question},
                    ],
                },
                # The very first request can be slow while the model loads
                # into memory, so give it some room.
                timeout=120,
            )
            response.raise_for_status()
            data = response.json()
            answer = data["choices"][0]["message"]["content"].strip()
            context["answer"] = answer
            context["cached"] = False
            context["elapsed"] = round(time.monotonic() - started, 1)

            # ...and Step 3: write it back to the cache for next time.
            if cache is not None:
                try:
                    cache.set(cache_key, answer, ex=CACHE_TTL)
                except redis.RedisError:
                    pass  # caching is best-effort; never fail the request
        except requests.exceptions.RequestException as exc:
            context["error"] = (
                f"Could not reach the model at {LLM_BASE_URL}. Is Docker Model "
                f"Runner enabled and has the '{LLM_MODEL}' model been pulled? "
                f"(details: {exc})"
            )
        except (KeyError, ValueError) as exc:
            context["error"] = f"Got an unexpected response from the model: {exc}"

    return render(request, "polls/ask.html", context)


class ResultsView(generic.DetailView):
    model = Question
    template_name = 'polls/results.html'
