import { Router } from 'express';
import { findPlaces } from '../places/index.js';
import { getNudgeById, getNudgesFor } from '../mocks.js';
import { requireDemoUser, type DemoRequest } from '../middleware.js';
import type { Suggestion } from '../types.js';

export const nudgesRouter = Router();

nudgesRouter.get('/nudges', requireDemoUser, (req, res) => {
  const user = (req as DemoRequest).demoUser;
  res.json(getNudgesFor(user.id));
});

nudgesRouter.get('/nudges/:id/suggestions', requireDemoUser, async (req, res) => {
  const nudge = getNudgeById(req.params.id);
  if (!nudge) {
    res.status(404).json({ error: 'Nudge not found' });
    return;
  }
  const near = process.env.DEMO_LOCATION ?? 'PCL Library UT Austin';
  const coffee = await findPlaces('coffee', near);
  const suggestions: Suggestion[] = [
    {
      gestureType: 'drop_off',
      title: 'Drop off an oat latte',
      detail: `Grab coffee near ${near} and leave it with Maya.`,
      place: coffee[0],
    },
    {
      gestureType: 'hangout',
      title: 'Sit with her at PCL',
      detail: 'She likes company during midterm week — a quiet study buddy helps.',
      place: {
        name: 'PCL Library',
        address: near,
        openNow: true,
      },
    },
    {
      gestureType: 'message',
      title: 'Send a check-in',
      detail: nudge.message,
    },
  ];
  res.json({ nudge, suggestions });
});
