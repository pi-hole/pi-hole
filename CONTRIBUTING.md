# Contributors Guide

Please read and understand the contribution guide before creating an issue or pull request.

## Etiquette

- Our goal for Pi-hole is **stability before features**. This means we focus on squashing critical bugs before adding new features. Often, we can do both in tandem, but bugs will take priority over a new feature.
- Pi-hole is open source and [powered by donations](https://pi-hole.net/donate/), and as such, we give our **free time** to build, maintain, and **provide user support** for this project. It would be extremely unfair for us to suffer abuse or anger for our hard work, so please take a moment to consider that.
- Please be considerate towards the developers and other users when raising issues or presenting pull requests.
- Respect our decision(s), and do not be upset or abusive if your submission is not used.

## Viability

When requesting or submitting new features, first consider whether it might be useful to others. Open source projects are used by many people, who may have entirely different needs to your own. Think about whether or not your feature is likely to be used by other users of the project.

## Procedure

**Before filing an issue:**

- Attempt to replicate and **document** the problem, to ensure that it wasn't a coincidental incident.
- Check to make sure your feature suggestion isn't already present within the project.
- Check the pull requests tab to ensure that the bug doesn't have a fix in progress.
- Check the pull requests tab to ensure that the feature isn't already in progress.

**Before submitting a pull request:**

- Check the codebase to ensure that your feature doesn't already exist.
- Check the pull requests to ensure that another person hasn't already submitted the feature or fix.
- Read and understand the [DCO guidelines](https://docs.pi-hole.net/guides/github/contributing/) for the project.

## Technical Requirements

- Submit Pull Requests to the **development branch only**.
- Before Submitting your Pull Request, merge `development` with your new branch and fix any conflicts. (Make sure you don't break anything in development!)
- Please use the [Google Style Guide for Shell](https://google.github.io/styleguide/shell.xml) for your code submission styles.
- Commit Unix line endings.
- Please use the Pi-hole brand: **Pi-hole** (Take a special look at the capitalized 'P' and a low 'h' with a hyphen)
- (Optional fun) keep to the theme of Star Trek/black holes/gravity.

## Forking and Cloning from GitHub to GitHub

1. Fork <https://github.com/pi-hole/pi-hole/> to a repo under a namespace you control, or have permission to use, for example: `https://github.com/<your_namespace>/<your_repo_name>/`. You can do this from the github.com website.
2. Clone `https://github.com/<your_namespace>/<your_repo_name>/` with the tool of you choice.
3. To keep your fork in sync with our repo, add an upstream remote for pi-hole/pi-hole to your repo.

    ```bash
    git remote add upstream https://github.com/pi-hole/pi-hole.git
    ```

4. Checkout the `development` branch from your fork `https://github.com/<your_namespace>/<your_repo_name>/`.
5. Create a topic/branch, based on the `development` branch code. *Bonus fun to keep to the theme of Star Trek/black holes/gravity.*
6. Make your changes and commit to your topic branch in your repo.
7. Rebase your commits and squash any insignificant commits. See the notes below for an example.
8. Merge `development` your branch and fix any conflicts.
9. Open a Pull Request to merge your topic branch into our repo's `development` branch.

- Keep in mind the technical requirements from above.

## Forking and Cloning from GitHub to other code hosting sites

- Forking is a GitHub concept and cannot be done from GitHub to other git-based code hosting sites. However, those sites may be able to mirror a GitHub repo.

1. To contribute from another code hosting site, you must first complete the steps above to fork our repo to a GitHub namespace you have permission to use, for example: `https://github.com/<your_namespace>/<your_repo_name>/`.
2. Create a repo in your code hosting site, for example: `https://gitlab.com/<your_namespace>/<your_repo_name>/`
3. Follow the instructions from your code hosting site to create a mirror between `https://github.com/<your_namespace>/<your_repo_name>/` and `https://gitlab.com/<your_namespace>/<your_repo_name>/`.
4. When you are ready to create a Pull Request (PR), follow the steps `(starting at step #6)` from [Forking and Cloning from GitHub to GitHub](#forking-and-cloning-from-github-to-github) and create the PR from `https://github.com/<your_namespace>/<your_repo_name>/`.

## Notes for squashing commits with rebase

- To rebase your commits and squash previous commits, you can use:

    ```bash
    git rebase -i your_topic_branch~(number of commits to combine)
    ```

- For more details visit [gitready.com](http://gitready.com/advanced/2009/02/10/squashing-commits-with-rebase.html)

1. The following would combine the last four commits in the branch `mytopic`.

    ```bash
    git rebase -i mytopic~4
    ```

2. An editor window opens with the most recent commits indicated: (edit the commands to the left of the commit ID)

    ```gitattributes
    pick 9dff55b2 existing commit comments
    squash ebb1a730 existing commit comments
    squash 07cc5b50 existing commit comments
    reword 9dff55b2 existing commit comments
    ```

3. Save and close the editor. The next editor window opens: (edit the new commit message). *If you select reword for a commit, an additional editor window will open for you to edit the comment.*

    ```bash
    new commit comments
    Signed-off-by: yourname <your email address>
    ```

4. Save and close the editor for the rebase process to execute. The terminal output should say something like the following:

    ```bash
    Successfully rebased and updated refs/heads/mytopic.
    ```

5. Once you have a successful rebase, and before you sync your local clone, you have to force push origin to update your repo:

    ```bash
    git push -f origin
    ```

6. Continue on from step #7 from [Forking and Cloning from GitHub to GitHub](#forking-and-cloning-from-github-to-github)
