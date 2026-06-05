# Maestro flows

Run the Home timeline smoke flows after building the simulator app:

```sh
maestro test .maestro/action-menu.yaml .maestro/timeline-scroll.yaml .maestro/timeline-ogp-swipe.yaml .maestro/post-detail.yaml
```

The flows intentionally check only stable smoke behavior:
- the Home timeline appears
- the root row is reachable by accessibility identifier
- the More action long press opens the shared floating menu
- vertical scrolling still works
- swiping from an OGP card still triggers row swipe actions
- tapping a post body opens the post detail screen
